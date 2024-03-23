locals {
  bucket_name     = "oidc-provider-${var.env}-${random_string.bucket_suffix.result}"
  issuer_hostpath = "s3.${data.aws_region.current.name}.amazonaws.com/${local.bucket_name}"
}

resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
}

data "aws_region" "current" {}

# Deploy AWS Cloud Provider
data "http" "aws_ccm_role_binding" {
  url = "https://raw.githubusercontent.com/kubernetes/cloud-provider-aws/master/examples/existing-cluster/base/apiserver-authentication-reader-role-binding.yaml"
}

resource "kubectl_manifest" "aws_ccm_role_binding" {
  yaml_body = data.http.aws_ccm_role_binding.response_body
}

data "http" "aws_ccm_daemon_set" {
  url = "https://raw.githubusercontent.com/kubernetes/cloud-provider-aws/master/examples/existing-cluster/base/aws-cloud-controller-manager-daemonset.yaml"
}

resource "kubectl_manifest" "aws_ccm_daemon_set" {
  yaml_body = data.http.aws_ccm_daemon_set.response_body
}

data "http" "aws_ccm_cluster_role_binding" {
  url = "https://raw.githubusercontent.com/kubernetes/cloud-provider-aws/master/examples/existing-cluster/base/cluster-role-binding.yaml"
}

resource "kubectl_manifest" "aws_ccm_cluster_role_binding" {
  yaml_body = data.http.aws_ccm_cluster_role_binding.response_body
}

data "http" "aws_ccm_cluster_role" {
  url = "https://raw.githubusercontent.com/kubernetes/cloud-provider-aws/master/examples/existing-cluster/base/cluster-role.yaml"
}

resource "kubectl_manifest" "aws_ccm_cluster_role" {
  yaml_body = data.http.aws_ccm_cluster_role.response_body
}

data "http" "aws_ccm_service_account" {
  url = "https://raw.githubusercontent.com/kubernetes/cloud-provider-aws/master/examples/existing-cluster/base/service-account.yaml"
}

resource "kubectl_manifest" "aws_ccm_service_account" {
  yaml_body = data.http.aws_ccm_service_account.response_body
}

resource "aws_s3_bucket" "oidc" {
  bucket = local.bucket_name

  tags = var.tags
}

resource "aws_s3_bucket_ownership_controls" "oidc" {
  bucket = aws_s3_bucket.oidc.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "oidc" {
  bucket = aws_s3_bucket.oidc.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_acl" "oidc" {
  bucket = aws_s3_bucket.oidc.id
  acl    = "public-read"

  depends_on = [
    aws_s3_bucket_ownership_controls.oidc,
    aws_s3_bucket_public_access_block.oidc,
  ]
}

resource "aws_s3_object" "discovery" {
  bucket  = aws_s3_bucket.oidc.bucket
  key     = ".well-known/openid-configuration"
  content = <<-EOF
    {
      "issuer": "https://${local.issuer_hostpath}",
      "jwks_uri": "https://${local.issuer_hostpath}/keys.json",
      "authorization_endpoint": "urn:kubernetes:programmatic_authorization",
      "response_types_supported": [
          "id_token"
      ],
      "subject_types_supported": [
          "public"
      ],
      "id_token_signing_alg_values_supported": [
          "RS256"
      ],
      "claims_supported": [
          "sub",
          "iss"
      ]
    }
  EOF
  acl     = "public-read"
}

resource "null_resource" "keys" {
  triggers = {
    issuer_hostpath = local.issuer_hostpath
  }

  # generate keys.json file
  provisioner "local-exec" {
    command = "go run main.go -key ../cluster-bootstrap/sa-signer.key.pub | jq '.keys += [.keys[0]] | .keys[1].kid = \"\"' > keys.json"
  }
}

resource "aws_s3_object" "keys" {
  bucket = aws_s3_bucket.oidc.bucket
  key    = "keys.json"
  source = "keys.json"
  acl    = "public-read"

  depends_on = [null_resource.keys]

  lifecycle {
    replace_triggered_by = [null_resource.keys]
  }
}

# Install cert-manager, a pre-requisite 
data "http" "cert_manager" {
  url = "https://github.com/cert-manager/cert-manager/releases/download/${var.cert_manager_version}/cert-manager.yaml"
}

# Grab EKS pod identity mutating webhook yaml files and deploy
data "http" "auth" {
  url = "https://raw.githubusercontent.com/aws/amazon-eks-pod-identity-webhook/master/deploy/auth.yaml"
}

resource "null_resource" "deployment" {
  triggers = {
    image = var.amazon_eks_pod_identity_webhook_image
  }

  # get deployment-base.yaml and substite image placeholder with value
  provisioner "local-exec" {
    command = "curl https://raw.githubusercontent.com/aws/amazon-eks-pod-identity-webhook/master/deploy/deployment-base.yaml | sed -e \"s|IMAGE|${var.amazon_eks_pod_identity_webhook_image}|g\" | sed -e \"s|sts.amazonaws.com|${var.audiences}|g\" | tee deployment.yaml"
  }
}

data "http" "mutatingwebhook" {
  url = "https://raw.githubusercontent.com/aws/amazon-eks-pod-identity-webhook/master/deploy/mutatingwebhook.yaml"
}

data "http" "service" {
  url = "https://raw.githubusercontent.com/aws/amazon-eks-pod-identity-webhook/master/deploy/service.yaml"
}

data "kubectl_file_documents" "cert_manager" {
  content = data.http.cert_manager.response_body
}

resource "kubectl_manifest" "cert_manager" {
  for_each  = data.kubectl_file_documents.cert_manager.manifests
  yaml_body = each.value

  depends_on = [
    aws_s3_bucket.oidc,
    aws_s3_object.discovery,
    kubectl_manifest.aws_ccm_cluster_role,
    kubectl_manifest.aws_ccm_cluster_role_binding,
    kubectl_manifest.aws_ccm_daemon_set,
    kubectl_manifest.aws_ccm_role_binding,
    kubectl_manifest.aws_ccm_service_account
  ]
}

data "kubectl_file_documents" "auth" {
  content = data.http.auth.response_body
}

resource "kubectl_manifest" "auth" {
  for_each  = data.kubectl_file_documents.auth.manifests
  yaml_body = each.value

  depends_on = [kubectl_manifest.cert_manager]
}

data "local_file" "deployment" {
  filename = "${path.module}/deployment.yaml"

  depends_on = [null_resource.deployment]
}

data "kubectl_file_documents" "deployment" {
  content = data.local_file.deployment.content
}

resource "kubectl_manifest" "deployment" {
  for_each  = data.kubectl_file_documents.deployment.manifests
  yaml_body = each.value

  depends_on = [kubectl_manifest.cert_manager]
}

data "kubectl_file_documents" "mutatingwebhook" {
  content = data.http.mutatingwebhook.response_body
}

resource "kubectl_manifest" "mutatingwebhook" {
  for_each  = data.kubectl_file_documents.mutatingwebhook.manifests
  yaml_body = each.value

  depends_on = [kubectl_manifest.cert_manager]
}

data "kubectl_file_documents" "service" {
  content = data.http.service.response_body
}

resource "kubectl_manifest" "service" {
  for_each  = data.kubectl_file_documents.service.manifests
  yaml_body = each.value

  depends_on = [kubectl_manifest.cert_manager]
}

# Create OIDC IdP with AWS IAM
data "tls_certificate" "oidc" {
  url = "https://${local.issuer_hostpath}"
}

resource "aws_iam_openid_connect_provider" "oidc" {
  client_id_list  = ["irsa"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]
  url             = data.tls_certificate.oidc.url
  tags            = tomap(merge({ Name = "OIDC-provider" }, var.tags))
}

output "oidc_issuer" {
  value = local.issuer_hostpath
}

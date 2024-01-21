locals {
  issuer_hostpath = "s3.${data.aws_region.current.name}.amazonaws.com/${aws_s3_bucket.oidc.bucket}"
}

data "aws_region" "current" {}

resource "aws_s3_bucket" "oidc" {
  bucket = "oidc-provider"

  tags = var.tags
}

resource "aws_s3_object" "discovery" {
  bucket = aws_s3_bucket.oidc.bucket
  key    = ".well-known/openid-configuration/discovery.json"
  source = <<-EOF
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
  acl    = "public-read"
}

resource "null_resource" "keys" {
  triggers = {
    issuer_hostpath = local.issuer_hostpath
  }

  # generate keys.json file
  provisioner "local-exec" {
    command = file("${path.module}/keys_gen.sh")
  }
}

resource "aws_s3_object" "discovery" {
  bucket = aws_s3_bucket.oidc.bucket
  key    = ".well-known/openid-configuration/discovery.json"
  source = "keys.json"
  acl    = "public-read"
}

# Grab EKS pod identity mutating webhook yaml files and deploy
data "http" "auth" {
  url = "https://github.com/aws/amazon-eks-pod-identity-webhook/blob/master/deploy/auth.yaml"

  depends_on = [
    aws_s3_bucket.oidc,
    aws_s3_object.discovery
  ]
}

data "http" "deployment_base" {
  url = "https://github.com/aws/amazon-eks-pod-identity-webhook/blob/master/deploy/deployment-base.yaml"

  depends_on = [
    aws_s3_bucket.oidc,
    aws_s3_object.discovery
  ]
}

data "http" "mutatingwebhook" {
  url = "https://github.com/aws/amazon-eks-pod-identity-webhook/blob/master/deploy/mutatingwebhook.yaml"

  depends_on = [
    aws_s3_bucket.oidc,
    aws_s3_object.discovery
  ]
}

data "http" "service" {
  url = "https://github.com/aws/amazon-eks-pod-identity-webhook/blob/master/deploy/service.yaml"

  depends_on = [
    aws_s3_bucket.oidc,
    aws_s3_object.discovery
  ]
}

resource "kubectl_manifest" "auth" {
  yaml_body = data.http.auth.body
}

resource "kubectl_manifest" "deployment_base" {
  yaml_body = data.http.deployment_base.body
}

resource "kubectl_manifest" "mutatingwebhook" {
  yaml_body = data.http.mutatingwebhook.body
}

resource "kubectl_manifest" "service" {
  yaml_body = data.http.service.body
}

output "oidc_issuer" {
  value = local.issuer_hostpath
}

locals {
  role_name         = "user-${var.user.name}-${var.user.role}-role"
  role_binding_name = "user-${var.user.name}-${var.user.role}-role-binding"
}

# create PK for CSR
resource "tls_private_key" "this" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "this" {
  private_key_pem = tls_private_key.this.private_key_pem

  subject {
    common_name = var.user.name
  }
}

resource "kubernetes_certificate_signing_request_v1" "this" {
  metadata {
    name   = "user-${var.user.name}-${var.user.role}"
    labels = var.labels
  }
  spec {
    usages      = ["client auth"]
    signer_name = "kubernetes.io/kube-apiserver-client"

    request = tls_cert_request.this.cert_request_pem
  }

  auto_approve = true
}

# grab cluster CA certificate
data "local_file" "cluster_ca" {
  filename = "../cluster-bootstrap/ca.crt"
}

resource "kubernetes_role_v1" "dev" {
  count = var.user.role == "dev" ? 1 : 0

  metadata {
    name      = local.role_name
    namespace = var.user.namespace
    labels    = var.labels
  }

  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["*"]
  }
}

resource "kubernetes_role_binding_v1" "dev" {
  count = var.user.role == "dev" ? 1 : 0

  metadata {
    name      = local.role_binding_name
    namespace = var.user.namespace
    labels    = var.labels
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.dev[0].metadata[0].name
  }

  subject {
    api_group = "rbac.authorization.k8s.io"
    kind      = "User"
    name      = var.user.name
  }
}

resource "kubernetes_cluster_role_v1" "admin" {
  count = var.user.role == "admin" ? 1 : 0

  metadata {
    name   = local.role_name
    labels = var.labels
  }

  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["*"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "admin" {
  count = var.user.role == "admin" ? 1 : 0

  metadata {
    name   = local.role_binding_name
    labels = var.labels
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.admin[0].metadata[0].name
  }

  subject {
    api_group = "rbac.authorization.k8s.io"
    kind      = "User"
    name      = var.user.name
  }
}

resource "local_file" "kubeconfig" {
  content = <<EOF
apiVersion: v1
kind: Config
preferences: {}
clusters:
- cluster:
    certificate-authority-data: ${data.local_file.cluster_ca.content_base64}
    server: https://${var.control_plane_ip}:6443
  name: ${var.cluster_name}
users:
- name: ${var.user.name}
  user:
    client-certificate-data: ${base64encode(kubernetes_certificate_signing_request_v1.this.certificate)}
    client-key-data: ${base64encode(tls_private_key.this.private_key_pem)}
contexts:
- context:
    cluster: ${var.cluster_name}
    user: ${var.user.name}
  name: ${var.user.name}@${var.cluster_name}
current-context: ${var.user.name}@${var.cluster_name}
EOF

  filename = "${path.root}/users/${var.user.name}/kubeconfig"
}

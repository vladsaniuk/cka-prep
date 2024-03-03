resource "kubernetes_service_account_v1" "this" {
  metadata {
    name      = var.service.name
    namespace = var.service.namespace
    labels    = var.labels
  }
}

resource "kubernetes_secret_v1" "this" {
  metadata {
    annotations = {
      "kubernetes.io/service-account.name" = var.service.name
    }

    generate_name = "${var.service.name}-"
  }

  type                           = "kubernetes.io/service-account-token"
  wait_for_service_account_token = true
}


resource "kubernetes_role_v1" "this" {
  metadata {
    name      = var.service.name
    namespace = var.service.namespace
    labels    = var.labels
  }

  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["*"]
  }
}

resource "kubernetes_role_binding_v1" "this" {
  metadata {
    name      = var.service.name
    namespace = var.service.namespace
    labels    = var.labels
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.this.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = var.service.name
    namespace = var.service.namespace
  }
}

resource "local_file" "kubeconfig" {
  content = <<EOF
apiVersion: v1
kind: Config
preferences: {}
clusters:
- cluster:
    certificate-authority-data: ${base64encode(kubernetes_secret_v1.this.data["ca.crt"])}
    server: https://${var.control_plane_ip}:6443
  name: ${var.cluster_name}
users:
- name: ${var.service.name}
  user:
    token: ${kubernetes_secret_v1.this.data["token"]}
contexts:
- context:
    cluster: ${var.cluster_name}
    user: ${var.service.name}
  name: ${var.service.name}@${var.cluster_name}
current-context: ${var.service.name}@${var.cluster_name}
EOF

  filename = "${path.root}/services/${var.service.name}/kubeconfig"
}

provider "kubernetes" {
  config_path = "../cluster-bootstrap/kubeconfig"
}

provider "helm" {
  kubernetes {
    config_path = "../cluster-bootstrap/kubeconfig"
  }
}

provider "kubectl" {
  config_path = "../cluster-bootstrap/kubeconfig"
}

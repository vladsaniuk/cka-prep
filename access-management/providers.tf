provider "tls" {}

provider "kubernetes" {
  config_path = "../cluster-bootstrap/kubeconfig"
}

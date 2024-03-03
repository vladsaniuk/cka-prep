# Get self-managed cluster details
data "terraform_remote_state" "cluster" {
  backend = "s3"
  config = {
    bucket         = "project-tfstate-bucket-dev"
    key            = "cka/cluster-bootstrap/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "state_lock"
  }
}

module "jack" {
  source           = "../modules/user"
  cluster_name     = data.terraform_remote_state.cluster.outputs.cluster_name
  control_plane_ip = data.terraform_remote_state.cluster.outputs.control_plane_ip
  user = {
    name      = "jack"
    role      = "dev"
    namespace = "default"
  }
  labels = var.tags
}

module "john" {
  source           = "../modules/user"
  cluster_name     = data.terraform_remote_state.cluster.outputs.cluster_name
  control_plane_ip = data.terraform_remote_state.cluster.outputs.control_plane_ip
  user = {
    name = "john"
    role = "admin"
  }
  labels = var.tags
}

module "application" {
  source           = "../modules/service"
  cluster_name     = data.terraform_remote_state.cluster.outputs.cluster_name
  control_plane_ip = data.terraform_remote_state.cluster.outputs.control_plane_ip
  service = {
    name      = "application"
    namespace = "default"
  }
  labels = var.tags
}

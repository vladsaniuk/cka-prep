terraform {
  backend "s3" {
    bucket         = "project-tfstate-bucket-dev"
    key            = "cka/nginx-ingress-conroller/terraform.tfstate"
    encrypt        = true
    dynamodb_table = "state_lock"
    region         = "us-east-1"
  }

  required_version = ">= 1.6.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.31.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.24.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.12.1"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "1.14.0"
    }
  }
}

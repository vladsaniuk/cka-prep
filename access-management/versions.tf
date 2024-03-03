terraform {
  backend "s3" {
    bucket         = "project-tfstate-bucket-dev"
    key            = "cka/access-management/terraform.tfstate"
    encrypt        = true
    dynamodb_table = "state_lock"
    region         = "us-east-1"
  }

  required_version = ">= 1.6.6"

  required_providers {
    tls = {
      source  = "hashicorp/tls"
      version = "4.0.5"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.24.0"
    }
  }
}

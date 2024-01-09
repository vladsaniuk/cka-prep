terraform {
  backend "s3" {
    bucket         = "vlad-sanyuk-tfstate-bucket-dev"
    key            = "cka/terraform.tfstate"
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
  }
}

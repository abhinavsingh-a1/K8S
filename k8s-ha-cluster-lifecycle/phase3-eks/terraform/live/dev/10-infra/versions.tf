terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.95" # eks module v20 requires >= 5.95, < 6.0
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }

  # terraform init -backend-config=backend.hcl   (key dev/10-infra.tfstate)
  backend "s3" {}
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      Stack       = "10-infra"
      ManagedBy   = "terraform"
      Owner       = var.owner
    }
  }
}

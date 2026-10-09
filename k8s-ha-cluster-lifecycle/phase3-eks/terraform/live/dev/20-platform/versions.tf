terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.95"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17" # 3.x changed the provider block syntax
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # terraform init -backend-config=backend.hcl   (key dev/20-platform.tfstate)
  backend "s3" {}
}

provider "aws" {
  region = local.infra.region

  default_tags {
    tags = {
      Project     = local.infra.project
      Environment = local.infra.environment
      Stack       = "20-platform"
      ManagedBy   = "terraform"
    }
  }
}

# Helm talks to the cluster created by 10-infra. The token is fetched at
# run time with the AWS CLI, so no long-lived credentials are stored.
provider "helm" {
  kubernetes {
    host                   = local.infra.cluster_endpoint
    cluster_ca_certificate = base64decode(local.infra.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", local.infra.cluster_name, "--region", local.infra.region]
    }
  }
}

# Stack 20-platform: what runs ON the cluster and the secrets the app needs.
# Reads stack 10-infra's outputs from its state file in S3.

variable "state_bucket" {
  description = "Same bucket as in backend.hcl (written by scripts/run.sh bootstrap)"
  type        = string
}

variable "state_region" {
  description = "Region of the state bucket"
  type        = string
  default     = "us-west-2"
}

variable "app_client_cidrs" {
  description = "Who may reach the app load balancer. Empty = same as the API allow-list."
  type        = list(string)
  default     = []
}

data "terraform_remote_state" "infra" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "dev/10-infra.tfstate"
    region = var.state_region
  }
}

data "aws_caller_identity" "current" {}

locals {
  infra            = data.terraform_remote_state.infra.outputs
  app_client_cidrs = length(var.app_client_cidrs) > 0 ? var.app_client_cidrs : local.infra.api_allowed_cidrs
}

module "app_secrets" {
  source             = "../../../modules/app-secrets"
  cluster_name       = local.infra.cluster_name
  region             = local.infra.region
  account_id         = data.aws_caller_identity.current.account_id
  secret_path_prefix = "${local.infra.project}/${local.infra.environment}" # k8s-ha-eks/dev
}

module "platform_addons" {
  source           = "../../../modules/platform-addons"
  app_client_cidrs = local.app_client_cidrs

  # The Pod Identity association must exist BEFORE the ESO pods start,
  # otherwise they run without AWS credentials.
  depends_on = [module.app_secrets]
}

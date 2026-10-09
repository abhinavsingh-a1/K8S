# Stack 10-infra: everything that takes long to build and rarely changes.
#   network -> eks_cluster
# Its outputs are read by stack 20-platform through terraform_remote_state.

data "http" "my_ip" {
  url = "https://checkip.amazonaws.com"
}

locals {
  name      = "${var.project}-${var.environment}" # k8s-ha-eks-dev
  api_cidrs = length(var.api_allowed_cidrs) > 0 ? var.api_allowed_cidrs : ["${chomp(data.http.my_ip.response_body)}/32"]
}

module "network" {
  source             = "../../../modules/network"
  name               = "${local.name}-vpc"
  vpc_cidr           = var.vpc_cidr
  single_nat_gateway = var.single_nat_gateway
}

module "eks_cluster" {
  source              = "../../../modules/eks-cluster"
  name                = local.name
  kubernetes_version  = var.kubernetes_version
  vpc_id              = module.network.vpc_id
  private_subnet_ids  = module.network.private_subnet_ids
  api_allowed_cidrs   = local.api_cidrs
  node_instance_types = var.node_instance_types
  node_min_size       = var.node_desired_size
  node_desired_size   = var.node_desired_size
  node_max_size       = var.node_desired_size * 2
}

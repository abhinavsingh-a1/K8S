# Environment "dev": wires the modules together.
# Order is decided by Terraform from the references between modules:
#   network -> security_groups -> (ssh_key) -> control_planes / workers -> nlb -> ansible hand-off

data "http" "my_ip" {
  url = "https://checkip.amazonaws.com"
}

locals {
  name             = "${var.project}-${var.environment}"            # k8s-ha-dev
  my_cidr          = "${chomp(data.http.my_ip.response_body)}/32"
  admin_cidrs      = length(var.admin_cidrs) > 0 ? var.admin_cidrs : [local.my_cidr]
  app_client_cidrs = length(var.app_client_cidrs) > 0 ? var.app_client_cidrs : local.admin_cidrs
  secret_prefix    = "${var.project}/${var.environment}"            # k8s-ha/dev
}

module "network" {
  source   = "../../modules/network"
  name     = local.name
  vpc_cidr = var.vpc_cidr
  az_count = 3
}

module "security_groups" {
  source            = "../../modules/security-groups"
  name              = local.name
  vpc_id            = module.network.vpc_id
  vpc_cidr          = module.network.vpc_cidr
  admin_cidrs       = local.admin_cidrs
  app_client_cidrs  = local.app_client_cidrs
  ingress_node_port = var.ingress_node_port
}

module "ssh_key" {
  source             = "../../modules/ssh-key"
  name               = "${local.name}-key"
  secret_path_prefix = local.secret_prefix
}

module "control_planes" {
  source             = "../../modules/k8s-nodes"
  name_prefix        = "${local.name}-cp"
  role               = "control-plane"
  node_count         = var.control_plane_count
  instance_type      = var.control_plane_instance_type
  subnet_ids         = module.network.public_subnet_ids
  security_group_ids = [module.security_groups.nodes_sg_id]
  key_name           = module.ssh_key.key_name
}

module "workers" {
  source             = "../../modules/k8s-nodes"
  name_prefix        = "${local.name}-worker"
  role               = "worker"
  node_count         = var.worker_count
  instance_type      = var.worker_instance_type
  subnet_ids         = module.network.public_subnet_ids
  security_group_ids = [module.security_groups.nodes_sg_id]
  key_name           = module.ssh_key.key_name
}

module "nlb" {
  source             = "../../modules/nlb"
  name               = "${local.name}-nlb"
  vpc_id             = module.network.vpc_id
  subnet_ids         = module.network.public_subnet_ids
  security_group_ids = [module.security_groups.nlb_sg_id]

  listeners = {
    api = {
      port        = 6443
      target_port = 6443
      target_ids  = module.control_planes.instance_ids
    }
    ingress = {
      port        = 80
      target_port = var.ingress_node_port
      target_ids  = module.workers.instance_ids
    }
  }
}

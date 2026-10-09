# Steps 2-5 on EKS:
#   - VPC: 3 AZs, public subnets (load balancers) + private subnets (nodes)
#   - EKS control plane: run by AWS, already HA (API servers + etcd spread over 3 AZs)
#   - Managed node group: 3 workers spread over the 3 AZs, auto-replaced if one fails

data "aws_availability_zones" "available" {
  state = "available"
}

data "http" "my_ip" {
  url = "https://checkip.amazonaws.com"
}

locals {
  azs          = slice(data.aws_availability_zones.available.names, 0, 3)
  api_cidrs    = length(var.api_allowed_cidrs) > 0 ? var.api_allowed_cidrs : ["${chomp(data.http.my_ip.response_body)}/32"]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.21"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets = [for i in range(3) : cidrsubnet(var.vpc_cidr, 4, i)]      # 10.30.0.0/20 ...
  public_subnets  = [for i in range(3) : cidrsubnet(var.vpc_cidr, 8, 48 + i)] # 10.30.48.0/24 ...

  enable_nat_gateway   = true
  single_nat_gateway   = var.single_nat_gateway
  enable_dns_hostnames = true

  # Tell Kubernetes where to put internet-facing / internal load balancers
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.37"

  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version

  # kubectl from your PC (restricted to your IP); nodes use the private endpoint
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = local.api_cidrs
  cluster_endpoint_private_access      = true

  # The IAM identity running terraform becomes cluster admin
  enable_cluster_creator_admin_permissions = true

  cluster_addons = {
    vpc-cni = {
      most_recent    = true
      before_compute = true # pod networking ready before nodes join
    }
    kube-proxy = {
      most_recent = true
    }
    coredns = {
      most_recent = true
    }
    eks-pod-identity-agent = {
      most_recent = true
    }
  }

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    workers = {
      ami_type       = "AL2023_x86_64_STANDARD" # x86: the app image is amd64
      instance_types = [var.node_instance_type]
      capacity_type  = "ON_DEMAND"

      min_size     = var.node_min_size
      desired_size = var.node_desired_size
      max_size     = var.node_max_size

      # Rolling maintenance: replace at most one node at a time on upgrades
      update_config = {
        max_unavailable = 1
      }

      labels = {
        role = "worker"
      }
    }
  }
}

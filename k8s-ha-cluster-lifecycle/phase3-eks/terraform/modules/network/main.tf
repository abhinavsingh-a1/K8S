# Module: network
# Thin company wrapper around the community VPC module: our defaults (3 AZs,
# private nodes, public load balancers, subnet tags for Kubernetes) are
# decided once here, so environments only pass a name and a CIDR.

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.21"

  name = var.name
  cidr = var.vpc_cidr
  azs  = local.azs

  # /20 private subnets for nodes + pods (VPC CNI gives pods VPC IPs)
  private_subnets = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i)]
  # /24 public subnets for load balancers and NAT
  public_subnets = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, 48 + i)]

  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway
  enable_dns_hostnames   = true

  # Where Kubernetes may place internet-facing / internal load balancers
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}

# Module: eks-cluster
# Company wrapper around the community EKS module. Decides once:
#   - private + IP-restricted public API endpoint
#   - Secrets envelope-encrypted with a KMS key (module default)
#   - control plane audit/api logs to CloudWatch
#   - core add-ons managed by EKS, incl. the Pod Identity agent
#   - one managed node group spread over all private subnets (= AZs)

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.37"

  cluster_name    = var.name
  cluster_version = var.kubernetes_version

  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = var.api_allowed_cidrs
  cluster_endpoint_private_access      = true

  # Kubernetes Secrets encrypted with a customer-managed KMS key
  # (the module creates the key; this states it explicitly)
  create_kms_key = true
  cluster_encryption_config = {
    resources = ["secrets"]
  }

  cluster_enabled_log_types              = ["api", "audit", "authenticator"]
  cloudwatch_log_group_retention_in_days = var.log_retention_days

  # Access entries (EKS API) instead of the old aws-auth ConfigMap.
  # The identity that runs terraform becomes cluster admin.
  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = true
  access_entries                           = var.admin_access_entries

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
    # Lets pods assume IAM roles (used by External Secrets Operator)
    eks-pod-identity-agent = {
      most_recent    = true
      before_compute = true
    }
  }

  vpc_id                   = var.vpc_id
  subnet_ids               = var.private_subnet_ids
  control_plane_subnet_ids = var.private_subnet_ids

  eks_managed_node_groups = {
    workers = {
      ami_type       = "AL2023_x86_64_STANDARD" # x86: the app image is amd64
      instance_types = var.node_instance_types
      capacity_type  = "ON_DEMAND"

      min_size     = var.node_min_size
      desired_size = var.node_desired_size
      max_size     = var.node_max_size

      # Rolling maintenance: AMI/version upgrades replace one node at a time
      update_config = {
        max_unavailable = 1
      }

      # Encrypted root volumes
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 30
            volume_type           = "gp3"
            encrypted             = true
            delete_on_termination = true
          }
        }
      }

      labels = {
        role = "worker"
      }
    }
  }
}

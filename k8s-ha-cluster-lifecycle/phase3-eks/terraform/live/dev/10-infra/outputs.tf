# Consumed by stack 20-platform (terraform_remote_state) and scripts.

output "region" {
  value = var.region
}

output "project" {
  value = var.project
}

output "environment" {
  value = var.environment
}

output "cluster_name" {
  value = module.eks_cluster.cluster_name
}

output "cluster_endpoint" {
  value = module.eks_cluster.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  value = module.eks_cluster.cluster_certificate_authority_data
}

output "vpc_id" {
  value = module.network.vpc_id
}

output "azs" {
  value = module.network.azs
}

output "api_allowed_cidrs" {
  value = local.api_cidrs
}

output "configure_kubectl" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks_cluster.cluster_name}"
}

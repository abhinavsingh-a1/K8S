output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  value = module.eks.cluster_certificate_authority_data
}

output "cluster_version" {
  value = module.eks.cluster_version
}

output "kms_key_arn" {
  description = "KMS key that encrypts Kubernetes Secrets"
  value       = module.eks.kms_key_arn
}

output "node_security_group_id" {
  value = module.eks.node_security_group_id
}

output "cluster_name" {
  value = local.infra.cluster_name
}

output "region" {
  value = local.infra.region
}

output "app_secret_name" {
  description = "Secrets Manager secret synced into Kubernetes by the ExternalSecret"
  value       = module.app_secrets.secret_name
}

output "eso_role_arn" {
  value = module.app_secrets.eso_role_arn
}

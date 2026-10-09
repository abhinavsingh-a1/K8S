output "api_endpoint" {
  description = "HA Kubernetes API endpoint (NLB)"
  value       = "https://${module.nlb.dns_name}:6443"
}

output "nlb_dns" {
  value = module.nlb.dns_name
}

output "control_planes" {
  value = module.control_planes.nodes
}

output "workers" {
  value = module.workers.nodes
}

output "ssh_key_secret_name" {
  description = "Fetch with: aws secretsmanager get-secret-value --secret-id <this>"
  value       = module.ssh_key.secret_name
}

output "admin_cidrs" {
  value = local.admin_cidrs
}

output "app_test_command" {
  value = "curl -H 'Host: foo.bar.com' http://${module.nlb.dns_name}/demo/"
}

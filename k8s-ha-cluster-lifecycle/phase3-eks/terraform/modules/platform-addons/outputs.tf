output "ingress_nginx_namespace" {
  value = helm_release.ingress_nginx.namespace
}

output "external_secrets_namespace" {
  value = helm_release.external_secrets.namespace
}

output "external_secrets_chart_version" {
  value = helm_release.external_secrets.version
}

variable "ingress_nginx_chart_version" {
  description = "helm search repo ingress-nginx/ingress-nginx --versions"
  type        = string
  default     = "4.13.3"
}

variable "external_secrets_chart_version" {
  description = "helm search repo external-secrets/external-secrets --versions"
  type        = string
  default     = "2.12.0"
}

variable "ingress_replicas" {
  type    = number
  default = 2
}

variable "app_client_cidrs" {
  description = "Who may reach the app's load balancer"
  type        = list(string)
}

variable "eso_namespace" {
  type    = string
  default = "external-secrets"
}

variable "eso_service_account" {
  type    = string
  default = "external-secrets"
}

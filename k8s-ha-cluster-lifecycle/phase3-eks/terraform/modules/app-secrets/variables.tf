variable "cluster_name" {
  type = string
}

variable "region" {
  type = string
}

variable "account_id" {
  type = string
}

variable "secret_path_prefix" {
  description = "Secrets Manager path, e.g. k8s-ha-eks/dev"
  type        = string
}

variable "secret_recovery_window_days" {
  description = "0 = delete immediately on destroy (dev). Production: 7-30."
  type        = number
  default     = 0
}

variable "eso_namespace" {
  type    = string
  default = "external-secrets"
}

variable "eso_service_account" {
  type    = string
  default = "external-secrets"
}

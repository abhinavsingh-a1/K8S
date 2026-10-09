variable "name" {
  description = "EC2 key pair name"
  type        = string
}

variable "secret_path_prefix" {
  description = "Secrets Manager path prefix, e.g. k8s-ha/dev"
  type        = string
}

variable "secret_recovery_window_days" {
  type    = number
  default = 0
}

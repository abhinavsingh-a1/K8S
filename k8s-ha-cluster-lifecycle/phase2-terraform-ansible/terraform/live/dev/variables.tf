variable "region" {
  type    = string
  default = "us-west-2"
}

variable "project" {
  type    = string
  default = "k8s-ha"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "owner" {
  description = "Tag: who is responsible for these resources"
  type        = string
  default     = "platform-team"
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "admin_cidrs" {
  description = "Who may SSH / reach NodePorts. Empty = your current public IP."
  type        = list(string)
  default     = []
}

variable "app_client_cidrs" {
  description = "Who may reach the app on port 80. Empty = same as admin_cidrs."
  type        = list(string)
  default     = []
}

variable "control_plane_count" {
  description = "Odd number: etcd needs a majority (3 tolerates 1 failure)"
  type        = number
  default     = 3

  validation {
    condition     = var.control_plane_count % 2 == 1
    error_message = "Use an odd number of control planes (1, 3, 5)."
  }
}

variable "worker_count" {
  type    = number
  default = 3
}

variable "control_plane_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "worker_instance_type" {
  type    = string
  default = "t3.small"
}

variable "ingress_node_port" {
  type    = number
  default = 30080
}

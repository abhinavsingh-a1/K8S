variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "project" {
  description = "Prefix for resource names and the Project tag"
  type        = string
  default     = "k8s-ha"
}

variable "vpc_cidr" {
  description = "CIDR of the new VPC (must not overlap the pod network 10.244.0.0/16)"
  type        = string
  default     = "10.20.0.0/16"
}

variable "allowed_cidr" {
  description = "Who may reach SSH, NodePorts and the NLB. Empty = your current public IP/32."
  type        = string
  default     = ""
}

variable "control_plane_count" {
  description = "Number of control planes. Use an odd number (3) so etcd keeps quorum when one fails."
  type        = number
  default     = 3

  validation {
    condition     = var.control_plane_count % 2 == 1
    error_message = "Use an odd number of control planes (1, 3, 5) - etcd needs a majority."
  }
}

variable "worker_count" {
  description = "Number of worker nodes (spread round-robin over 3 AZs)"
  type        = number
  default     = 3
}

variable "control_plane_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "worker_instance_type" {
  type    = string
  default = "t3.small"
}

variable "root_volume_gib" {
  type    = number
  default = 20
}

variable "ingress_node_port" {
  description = "NodePort of the NGINX Ingress controller (the NLB forwards port 80 here)"
  type        = number
  default     = 30080
}

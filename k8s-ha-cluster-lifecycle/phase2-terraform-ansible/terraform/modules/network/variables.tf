variable "name" {
  description = "Name prefix, e.g. k8s-ha-dev"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR. Must not overlap the pod network (10.244.0.0/16)."
  type        = string
}

variable "az_count" {
  description = "Number of availability zones (one public subnet each)"
  type        = number
  default     = 3
}

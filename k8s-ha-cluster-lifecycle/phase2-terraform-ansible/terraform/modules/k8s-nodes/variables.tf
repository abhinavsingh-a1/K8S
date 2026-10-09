variable "name_prefix" {
  description = "Instance names become <name_prefix>-1, -2, ..."
  type        = string
}

variable "role" {
  description = "control-plane or worker"
  type        = string

  validation {
    condition     = contains(["control-plane", "worker"], var.role)
    error_message = "role must be control-plane or worker."
  }
}

variable "node_count" {
  type = number
}

variable "instance_type" {
  type = string
}

variable "subnet_ids" {
  description = "Nodes are placed round-robin over these subnets"
  type        = list(string)
}

variable "security_group_ids" {
  type = list(string)
}

variable "key_name" {
  type = string
}

variable "root_volume_gib" {
  type    = number
  default = 20
}

variable "ami_ssm_parameter" {
  description = "Canonical's public SSM parameter for Ubuntu 24.04 amd64"
  type        = string
  default     = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

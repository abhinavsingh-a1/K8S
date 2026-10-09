variable "name" {
  type = string
}

variable "kubernetes_version" {
  description = "Use a version in STANDARD support (extended support costs ~6x)"
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "api_allowed_cidrs" {
  description = "Who may reach the public API endpoint"
  type        = list(string)
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_min_size" {
  type    = number
  default = 3
}

variable "node_desired_size" {
  type    = number
  default = 3
}

variable "node_max_size" {
  type    = number
  default = 6
}

variable "log_retention_days" {
  type    = number
  default = 7
}

variable "admin_access_entries" {
  description = "Extra IAM principals with cluster access (eks module access_entries format)"
  type        = any
  default     = {}
}

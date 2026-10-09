variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "admin_cidrs" {
  description = "CIDRs allowed to SSH and reach NodePorts"
  type        = list(string)
}

variable "app_client_cidrs" {
  description = "CIDRs allowed to reach the app on port 80"
  type        = list(string)
}

variable "ingress_node_port" {
  type    = number
  default = 30080
}

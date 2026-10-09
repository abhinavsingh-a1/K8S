variable "name" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "az_count" {
  type    = number
  default = 3
}

variable "single_nat_gateway" {
  description = "true = 1 NAT (cheap, dev). false = 1 NAT per AZ (prod: survives an AZ outage)."
  type        = bool
  default     = true
}

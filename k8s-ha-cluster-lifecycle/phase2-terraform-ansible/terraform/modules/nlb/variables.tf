variable "name" {
  description = "NLB name (max 32 chars); target groups are <name>-<listener key>"
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "security_group_ids" {
  type = list(string)
}

variable "listeners" {
  description = "Map: key => { port, target_port, target_ids }"
  type = map(object({
    port        = number
    target_port = number
    target_ids  = list(string)
  }))
}

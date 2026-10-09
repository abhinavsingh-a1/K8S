variable "region" {
  type    = string
  default = "us-west-2"
}

variable "project" {
  type    = string
  default = "k8s-ha-eks"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "owner" {
  type    = string
  default = "platform-team"
}

variable "vpc_cidr" {
  type    = string
  default = "10.30.0.0/16"
}

variable "single_nat_gateway" {
  type    = bool
  default = true
}

variable "kubernetes_version" {
  description = "aws eks describe-cluster-versions --region us-west-2 (pick STANDARD support)"
  type        = string
  default     = "1.34"
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_desired_size" {
  type    = number
  default = 3
}

variable "api_allowed_cidrs" {
  description = "Empty = your current public IP"
  type        = list(string)
  default     = []
}

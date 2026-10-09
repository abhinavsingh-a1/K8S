variable "region" {
  type    = string
  default = "us-west-2"
}

variable "cluster_name" {
  type    = string
  default = "k8s-ha-eks"
}

variable "kubernetes_version" {
  description = "EKS version. Pick one in STANDARD support (extended support costs 6x more): aws eks describe-cluster-versions --region us-west-2"
  type        = string
  default     = "1.34"
}

variable "vpc_cidr" {
  type    = string
  default = "10.30.0.0/16"
}

variable "single_nat_gateway" {
  description = "true = one NAT gateway (cheaper, fine for learning). false = one per AZ (production HA)."
  type        = bool
  default     = true
}

variable "node_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "node_min_size" {
  type    = number
  default = 3
}

variable "node_desired_size" {
  description = "3 = one worker per AZ"
  type        = number
  default     = 3
}

variable "node_max_size" {
  type    = number
  default = 6
}

variable "api_allowed_cidrs" {
  description = "Who may reach the public EKS API endpoint. Empty = your current public IP/32."
  type        = list(string)
  default     = []
}

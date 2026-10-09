# Module: security-groups
#   nodes : SSH + NodePorts from admins, all traffic between nodes,
#           API + ingress NodePort from the NLB (inside the VPC)
#   nlb   : app port 80 from allowed clients, API 6443 from anywhere
#           (nodes reach the internet-facing NLB from their PUBLIC IPs)

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

resource "aws_security_group" "nodes" {
  name        = "${var.name}-nodes"
  description = "Kubernetes nodes"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-nodes" }
}

resource "aws_security_group" "nlb" {
  name        = "${var.name}-nlb"
  description = "Kubernetes network load balancer"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name}-nlb" }
}

# ---------- nodes ----------

resource "aws_vpc_security_group_ingress_rule" "nodes_ssh" {
  for_each          = toset(var.admin_cidrs)
  security_group_id = aws_security_group.nodes.id
  description       = "SSH from admins"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

resource "aws_vpc_security_group_ingress_rule" "nodes_nodeports" {
  for_each          = toset(var.admin_cidrs)
  security_group_id = aws_security_group.nodes.id
  description       = "NodePorts from admins (debugging)"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 30000
  to_port           = 32767
}

resource "aws_vpc_security_group_ingress_rule" "nodes_self" {
  security_group_id            = aws_security_group.nodes.id
  description                  = "All traffic between nodes (API, kubelet, etcd, VXLAN)"
  referenced_security_group_id = aws_security_group.nodes.id
  ip_protocol                  = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "nodes_api_from_vpc" {
  security_group_id = aws_security_group.nodes.id
  description       = "API from the NLB (client IP not preserved -> NLB private IP)"
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 6443
  to_port           = 6443
}

resource "aws_vpc_security_group_ingress_rule" "nodes_ingress_from_vpc" {
  security_group_id = aws_security_group.nodes.id
  description       = "Ingress NodePort from the NLB"
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = var.ingress_node_port
  to_port           = var.ingress_node_port
}

resource "aws_vpc_security_group_egress_rule" "nodes_all" {
  security_group_id = aws_security_group.nodes.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ---------- nlb ----------

resource "aws_vpc_security_group_ingress_rule" "nlb_http" {
  for_each          = toset(var.app_client_cidrs)
  security_group_id = aws_security_group.nlb.id
  description       = "Application (Ingress) clients"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "nlb_api" {
  security_group_id = aws_security_group.nlb.id
  description       = "Kubernetes API: nodes (public IPs) and kubectl. TLS-authenticated."
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 6443
  to_port           = 6443
}

resource "aws_vpc_security_group_egress_rule" "nlb_all" {
  security_group_id = aws_security_group.nlb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

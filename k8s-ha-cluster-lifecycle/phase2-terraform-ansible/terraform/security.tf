# Step 2 (security): key pair + security groups.

data "http" "my_ip" {
  url = "https://checkip.amazonaws.com"
}

locals {
  allowed_cidr = var.allowed_cidr != "" ? var.allowed_cidr : "${chomp(data.http.my_ip.response_body)}/32"
}

# ---------- SSH key pair (private key is written for Ansible) ----------

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "this" {
  key_name   = "${var.project}-key"
  public_key = tls_private_key.ssh.public_key_openssh
}

resource "local_sensitive_file" "private_key" {
  filename        = "${path.module}/../ansible/${var.project}-key.pem"
  content         = tls_private_key.ssh.private_key_openssh
  file_permission = "0600"
}

# ---------- Nodes ----------

resource "aws_security_group" "nodes" {
  name        = "${var.project}-nodes"
  description = "kubeadm HA cluster nodes"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.project}-nodes" }
}

resource "aws_vpc_security_group_ingress_rule" "nodes_ssh" {
  security_group_id = aws_security_group.nodes.id
  description       = "SSH from you"
  cidr_ipv4         = local.allowed_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

resource "aws_vpc_security_group_ingress_rule" "nodes_nodeports" {
  security_group_id = aws_security_group.nodes.id
  description       = "NodePorts from you (e.g. 30007)"
  cidr_ipv4         = local.allowed_cidr
  ip_protocol       = "tcp"
  from_port         = 30000
  to_port           = 32767
}

resource "aws_vpc_security_group_ingress_rule" "nodes_self" {
  security_group_id            = aws_security_group.nodes.id
  description                  = "All traffic between nodes (API, kubelet, etcd, Flannel VXLAN)"
  referenced_security_group_id = aws_security_group.nodes.id
  ip_protocol                  = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "nodes_api_from_vpc" {
  security_group_id = aws_security_group.nodes.id
  description       = "Kubernetes API from the NLB (client IP not preserved)"
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

# ---------- Load balancer ----------

resource "aws_security_group" "nlb" {
  name        = "${var.project}-nlb"
  description = "kubeadm HA cluster load balancer"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.project}-nlb" }
}

resource "aws_vpc_security_group_ingress_rule" "nlb_http" {
  security_group_id = aws_security_group.nlb.id
  description       = "App (Ingress) from you"
  cidr_ipv4         = local.allowed_cidr
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

# The NLB is internet-facing, so its DNS name resolves to PUBLIC IPs even from
# inside the VPC: nodes arrive with their public IPs (which change on restart).
# 6443 is therefore open to all; the API still requires TLS certs / tokens.
# Enterprise alternative: a second, internal NLB for the API only.
resource "aws_vpc_security_group_ingress_rule" "nlb_api" {
  security_group_id = aws_security_group.nlb.id
  description       = "Kubernetes API (nodes and kubectl)"
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

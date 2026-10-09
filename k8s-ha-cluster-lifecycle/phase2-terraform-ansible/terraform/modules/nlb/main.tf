# Module: nlb
# Internet-facing Network Load Balancer with any number of TCP listeners,
# each forwarding to its own target group of instances.

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

locals {
  # Flatten listener => instance pairs for the attachments
  attachments = merge([
    for lname, l in var.listeners : {
      for idx, id in l.target_ids : "${lname}-${idx}" => {
        listener  = lname
        target_id = id
        port      = l.target_port
      }
    }
  ]...)
}

resource "aws_lb" "this" {
  name                             = var.name
  load_balancer_type               = "network"
  internal                         = false
  subnets                          = var.subnet_ids
  security_groups                  = var.security_group_ids
  enable_cross_zone_load_balancing = true
}

resource "aws_lb_target_group" "this" {
  for_each = var.listeners

  name                 = "${var.name}-${each.key}"
  port                 = each.value.target_port
  protocol             = "TCP"
  vpc_id               = var.vpc_id
  target_type          = "instance"
  deregistration_delay = 30

  # Hairpin fix: a node calling the NLB that lands on itself fails when the
  # client IP is preserved. kubeadm does exactly that during join.
  preserve_client_ip = false

  health_check {
    protocol            = "TCP"
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group_attachment" "this" {
  for_each = local.attachments

  target_group_arn = aws_lb_target_group.this[each.value.listener].arn
  target_id        = each.value.target_id
  port             = each.value.port
}

resource "aws_lb_listener" "this" {
  for_each = var.listeners

  load_balancer_arn = aws_lb.this.arn
  port              = each.value.port
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[each.key].arn
  }
}

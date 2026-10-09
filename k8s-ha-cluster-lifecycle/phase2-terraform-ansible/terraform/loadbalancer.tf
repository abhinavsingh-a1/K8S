# Network Load Balancer
#   :6443 -> control planes :6443  (HA Kubernetes API endpoint)
#   :80   -> workers :30080        (NGINX Ingress NodePort)

resource "aws_lb" "this" {
  name                             = "${var.project}-nlb"
  load_balancer_type               = "network"
  internal                         = false
  subnets                          = aws_subnet.public[*].id
  security_groups                  = [aws_security_group.nlb.id]
  enable_cross_zone_load_balancing = true
}

resource "aws_lb_target_group" "api" {
  name                 = "${var.project}-api"
  port                 = 6443
  protocol             = "TCP"
  vpc_id               = aws_vpc.this.id
  target_type          = "instance"
  deregistration_delay = 30

  # A control plane that calls the NLB and lands on itself ("hairpin")
  # fails when the client IP is preserved. kubeadm does exactly that.
  preserve_client_ip = false

  health_check {
    protocol            = "TCP"
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group" "ingress" {
  name                 = "${var.project}-ingress"
  port                 = var.ingress_node_port
  protocol             = "TCP"
  vpc_id               = aws_vpc.this.id
  target_type          = "instance"
  deregistration_delay = 30
  preserve_client_ip   = false

  health_check {
    protocol            = "TCP"
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_target_group_attachment" "api" {
  count            = var.control_plane_count
  target_group_arn = aws_lb_target_group.api.arn
  target_id        = aws_instance.control_plane[count.index].id
  port             = 6443
}

resource "aws_lb_target_group_attachment" "ingress" {
  count            = var.worker_count
  target_group_arn = aws_lb_target_group.ingress.arn
  target_id        = aws_instance.worker[count.index].id
  port             = var.ingress_node_port
}

resource "aws_lb_listener" "api" {
  load_balancer_arn = aws_lb.this.arn
  port              = 6443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ingress.arn
  }
}

# Step 3: control planes and workers, round-robin over 3 AZs.

data "aws_ssm_parameter" "ubuntu_2404" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

locals {
  common_instance = {
    ami                    = data.aws_ssm_parameter.ubuntu_2404.value
    key_name               = aws_key_pair.this.key_name
    vpc_security_group_ids = [aws_security_group.nodes.id]
  }
}

resource "aws_instance" "control_plane" {
  count                  = var.control_plane_count
  ami                    = local.common_instance.ami
  instance_type          = var.control_plane_instance_type
  key_name               = local.common_instance.key_name
  vpc_security_group_ids = local.common_instance.vpc_security_group_ids
  subnet_id              = aws_subnet.public[count.index % 3].id

  root_block_device {
    volume_size           = var.root_volume_gib
    volume_type           = "gp3"
    delete_on_termination = true
  }

  metadata_options {
    http_tokens                 = "required" # IMDSv2 only
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 2
  }

  # A new Ubuntu AMI must not replace running control planes.
  lifecycle {
    ignore_changes = [ami]
  }

  tags = {
    Name = "${var.project}-cp-${count.index + 1}"
    Role = "control-plane"
  }
}

resource "aws_instance" "worker" {
  count                  = var.worker_count
  ami                    = local.common_instance.ami
  instance_type          = var.worker_instance_type
  key_name               = local.common_instance.key_name
  vpc_security_group_ids = local.common_instance.vpc_security_group_ids
  subnet_id              = aws_subnet.public[count.index % 3].id

  root_block_device {
    volume_size           = var.root_volume_gib
    volume_type           = "gp3"
    delete_on_termination = true
  }

  metadata_options {
    http_tokens                 = "required"
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 2
  }

  lifecycle {
    ignore_changes = [ami]
  }

  tags = {
    Name = "${var.project}-worker-${count.index + 1}"
    Role = "worker"
  }
}

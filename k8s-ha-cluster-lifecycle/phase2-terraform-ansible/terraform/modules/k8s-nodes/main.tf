# Module: k8s-nodes
# A group of identical EC2 nodes with one role (control-plane or worker),
# spread round-robin across the given subnets (= availability zones).
# Called twice by the environment: once per role.

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

data "aws_ssm_parameter" "ubuntu" {
  name = var.ami_ssm_parameter
}

resource "aws_instance" "this" {
  count = var.node_count

  ami                    = data.aws_ssm_parameter.ubuntu.value
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = var.security_group_ids
  subnet_id              = var.subnet_ids[count.index % length(var.subnet_ids)]

  root_block_device {
    volume_size           = var.root_volume_gib
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_tokens                 = "required" # IMDSv2 only
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 2
  }

  # A newer Ubuntu AMI must not replace running Kubernetes nodes.
  lifecycle {
    ignore_changes = [ami]
  }

  # Tags drive the Ansible dynamic inventory (aws_ec2 plugin):
  #   Role      -> groups control_plane / workers
  #   Bootstrap -> the ONE control plane that runs `kubeadm init`
  tags = {
    Name      = "${var.name_prefix}-${count.index + 1}"
    Role      = var.role
    Bootstrap = var.role == "control-plane" && count.index == 0 ? "true" : "false"
  }
}

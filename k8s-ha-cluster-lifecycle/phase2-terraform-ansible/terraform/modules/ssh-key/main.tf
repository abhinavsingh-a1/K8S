# Module: ssh-key
# Generates an SSH key pair, registers the public half in EC2 and stores the
# private half in AWS Secrets Manager. Nothing is written to disk: operators
# fetch the key with `scripts/run.sh fetch-key` (IAM controls who may).

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    tls = {
      source = "hashicorp/tls"
    }
  }
}

resource "tls_private_key" "this" {
  algorithm = "ED25519"
}

resource "aws_key_pair" "this" {
  key_name   = var.name
  public_key = tls_private_key.this.public_key_openssh
}

resource "aws_secretsmanager_secret" "private_key" {
  name        = "${var.secret_path_prefix}/ssh-private-key"
  description = "SSH private key for ${var.name} EC2 nodes"

  # 0 = delete immediately on destroy, so the same name can be reused at
  # once. Production would keep the default 30-day recovery window.
  recovery_window_in_days = var.secret_recovery_window_days
}

resource "aws_secretsmanager_secret_version" "private_key" {
  secret_id     = aws_secretsmanager_secret.private_key.id
  secret_string = tls_private_key.this.private_key_openssh
}

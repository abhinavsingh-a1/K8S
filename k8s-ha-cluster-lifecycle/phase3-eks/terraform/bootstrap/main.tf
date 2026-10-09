# One-time setup: the S3 bucket that stores Terraform state for every
# environment of this project. It uses LOCAL state itself (chicken-and-egg),
# so keep its terraform.tfstate file safe, or import the bucket if lost.

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.95"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Stack     = "bootstrap"
    }
  }
}

variable "region" {
  type    = string
  default = "us-west-2"
}

variable "project" {
  type    = string
  default = "k8s-ha-eks"
}

data "aws_caller_identity" "current" {}

locals {
  # Bucket names are global: account ID + region make it unique.
  bucket_name = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}-${var.region}"
}

resource "aws_s3_bucket" "state" {
  bucket = local.bucket_name

  # Allows `terraform destroy` of the bootstrap when you are completely done.
  # In a real company this would be false and the bucket kept forever.
  force_destroy = true
}

# Every state change creates a new object version: you can roll back.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# State contains secrets (e.g. the generated Django secret key) - encrypt at rest.
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Only HTTPS access to the state bucket.
resource "aws_s3_bucket_policy" "tls_only" {
  bucket = aws_s3_bucket.state.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.state]
}

output "state_bucket" {
  value = aws_s3_bucket.state.bucket
}

# Paste into live/<env>/backend.hcl (scripts/run.sh does it for you).
# One state file per stack. scripts/run.sh writes these into the stacks.
output "backend_hcl_infra" {
  value = <<-EOT
    bucket       = "${aws_s3_bucket.state.bucket}"
    key          = "dev/10-infra.tfstate"
    region       = "${var.region}"
    encrypt      = true
    use_lockfile = true
  EOT
}

output "backend_hcl_platform" {
  value = <<-EOT
    bucket       = "${aws_s3_bucket.state.bucket}"
    key          = "dev/20-platform.tfstate"
    region       = "${var.region}"
    encrypt      = true
    use_lockfile = true
  EOT
}

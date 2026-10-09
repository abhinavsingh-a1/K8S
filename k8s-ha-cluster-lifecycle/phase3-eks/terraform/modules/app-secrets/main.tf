# Module: app-secrets
# 1. Generates the app's secret values and stores them in AWS Secrets Manager
#    (source of truth; rotate there, not in Kubernetes).
# 2. Creates an IAM role that may ONLY read these secrets, and binds it to
#    the External Secrets Operator service account with EKS Pod Identity.
#    No AWS keys anywhere in the cluster.

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}

resource "random_password" "django_secret_key" {
  length  = 50
  special = false
}

resource "aws_secretsmanager_secret" "app" {
  name                    = "${var.secret_path_prefix}/django"
  description             = "Django application secrets (${var.cluster_name})"
  recovery_window_in_days = var.secret_recovery_window_days
}

resource "aws_secretsmanager_secret_version" "app" {
  secret_id = aws_secretsmanager_secret.app.id
  secret_string = jsonencode({
    DJANGO_SECRET_KEY = random_password.django_secret_key.result
  })
}

# ---------- IAM role for External Secrets Operator (Pod Identity) ----------

data "aws_iam_policy_document" "eso_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eso" {
  name               = "${var.cluster_name}-external-secrets"
  assume_role_policy = data.aws_iam_policy_document.eso_trust.json
}

# Least privilege: read only the secrets under this app's path
data "aws_iam_policy_document" "eso_read" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = ["arn:aws:secretsmanager:${var.region}:${var.account_id}:secret:${var.secret_path_prefix}/*"]
  }
}

resource "aws_iam_role_policy" "eso_read" {
  name   = "read-app-secrets"
  role   = aws_iam_role.eso.id
  policy = data.aws_iam_policy_document.eso_read.json
}

resource "aws_eks_pod_identity_association" "eso" {
  cluster_name    = var.cluster_name
  namespace       = var.eso_namespace
  service_account = var.eso_service_account
  role_arn        = aws_iam_role.eso.arn
}

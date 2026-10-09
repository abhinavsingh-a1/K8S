output "secret_name" {
  description = "Secrets Manager secret the ExternalSecret reads"
  value       = aws_secretsmanager_secret.app.name
}

output "secret_arn" {
  value = aws_secretsmanager_secret.app.arn
}

output "eso_role_arn" {
  value = aws_iam_role.eso.arn
}

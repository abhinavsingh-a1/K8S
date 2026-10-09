output "key_name" {
  value = aws_key_pair.this.key_name
}

output "secret_name" {
  description = "Secrets Manager secret holding the private key"
  value       = aws_secretsmanager_secret.private_key.name
}

output "secret_arn" {
  value = aws_secretsmanager_secret.private_key.arn
}

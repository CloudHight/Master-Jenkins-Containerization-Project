output "nexus_admin_secret_arn" {
  value = aws_secretsmanager_secret.nexus_admin.arn
}

output "sonar_db_secret_arn" {
  value = aws_secretsmanager_secret.sonar_db.arn
}

output "ssh_private_key_secret_arn" {
  value = aws_secretsmanager_secret.ssh_private_key.arn
}

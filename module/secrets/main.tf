# Nexus admin password (used by Nexus, Jenkins, Ansible and the stage/prod docker hosts)
resource "random_password" "nexus_admin" {
  length  = 24
  special = false
}

resource "aws_secretsmanager_secret" "nexus_admin" {
  name_prefix             = "${var.name}/nexus-admin-"
  description             = "Nexus admin password"
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "nexus_admin" {
  secret_id     = aws_secretsmanager_secret.nexus_admin.id
  secret_string = random_password.nexus_admin.result
}

# SonarQube local PostgreSQL password
resource "random_password" "sonar_db" {
  length  = 24
  special = false
}

resource "aws_secretsmanager_secret" "sonar_db" {
  name_prefix             = "${var.name}/sonarqube-db-"
  description             = "SonarQube database password"
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "sonar_db" {
  secret_id     = aws_secretsmanager_secret.sonar_db.id
  secret_string = random_password.sonar_db.result
}

# SSH private key used by the Ansible server to reach the stage/prod hosts
resource "aws_secretsmanager_secret" "ssh_private_key" {
  name_prefix             = "${var.name}/ssh-private-key-"
  description             = "SSH private key for Ansible"
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "ssh_private_key" {
  secret_id     = aws_secretsmanager_secret.ssh_private_key.id
  secret_string = var.ssh_private_key
}

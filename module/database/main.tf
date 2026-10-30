
#  RDS Subnet Group
resource "aws_db_subnet_group" "team1_db_subnet_group" {
  name        = "${var.name}-db_subnet"
  subnet_ids  = [var.private_subnet1_id, var.private_subnet2_id] # Use private subnets for security
  description = "Subnet group for Multi-AZ RDS deployment"

  tags = {
    Name = "${var.name}-db-Subnet-Group"
  }
}
# Unique suffix so repeated destroys don't collide on the final snapshot name
resource "random_id" "final_snapshot" {
  byte_length = 4
}

# Export MySQL logs to CloudWatch (log groups created here so they are KMS encrypted)
resource "aws_cloudwatch_log_group" "rds" {
  for_each          = toset(["error", "slowquery"])
  name              = "/aws/rds/instance/${var.name}-db/${each.key}"
  retention_in_days = 90
  kms_key_id        = var.kms_key_arn
}

resource "aws_db_instance" "team1_mysql_database" {
  identifier             = "${var.name}-db"
  db_subnet_group_name   = aws_db_subnet_group.team1_db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.RDS-security-group.id]
  db_name                = "petclinic"
  # High Availability
  multi_az = false

  # Engine Settings
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t3.micro"
  parameter_group_name = "default.mysql5.7"

  # Storage (encrypted with the customer managed KMS key)
  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true
  kms_key_id        = var.kms_key_arn

  # Credentials: master password generated and stored by RDS in AWS Secrets Manager
  username                      = "petclinicadmin"
  manage_master_user_password   = true
  master_user_secret_kms_key_id = var.kms_key_arn

  # Backup & Maintenance
  backup_retention_period   = 7
  backup_window             = "02:00-03:00"
  copy_tags_to_snapshot     = true
  delete_automated_backups  = false
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.name}-db-final-${random_id.final_snapshot.hex}"

  # Observability
  enabled_cloudwatch_logs_exports = ["error", "slowquery"]

  # Security
  publicly_accessible = false
  deletion_protection = var.deletion_protection

  tags = {
    Name   = "${var.name}-db"
    Backup = var.name
  }

  depends_on = [aws_cloudwatch_log_group.rds]
}
#RDS security group
resource "aws_security_group" "RDS-security-group" {
  name        = "${var.name}-rds-sg"
  description = "RDS Security group"
  vpc_id      = var.vpc-id

  ingress {
    description     = "mysqlport"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [var.bastion-security-group, var.stage-security-group, var.prod-security-group]
  }
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-rds-sg"
  }
}


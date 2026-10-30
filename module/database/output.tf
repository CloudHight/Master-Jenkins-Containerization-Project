output "db_endpoint" {
  value = aws_db_instance.team1_mysql_database.endpoint
}

output "db_identifier" {
  value = aws_db_instance.team1_mysql_database.identifier
}

output "db_secret_arn" {
  value = aws_db_instance.team1_mysql_database.master_user_secret[0].secret_arn
}

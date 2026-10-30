output "nexus_registry" {
  value = module.nexus.nexus_registry
}

output "nexus_admin_secret_arn" {
  value = module.secrets.nexus_admin_secret_arn
}

output "db_secret_arn" {
  value = module.database.db_secret_arn
}

output "alerts_topic_arn" {
  value = module.monitoring.sns_topic_arn
}

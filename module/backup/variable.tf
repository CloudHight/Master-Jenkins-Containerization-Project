variable "name" {
  description = "Resources tagged Backup = <name> are backed up"
}
variable "kms_key_arn" {}
variable "sns_topic_arn" {}

variable "daily_retention_days" {
  default = 35
}

variable "weekly_retention_days" {
  default = 90
}

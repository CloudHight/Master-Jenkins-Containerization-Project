variable "name" {}
variable "region" {}
variable "kms_key_arn" {}
variable "vpc_id" {}

variable "alert_email" {
  type        = string
  default     = ""
  description = "E-mail address subscribed to the alert topic (empty = no subscription)"
}

variable "log_retention_days" {
  default = 90
}

variable "instances" {
  type        = map(string)
  default     = {}
  description = "Standalone EC2 instance IDs to monitor, keyed by a static name"
}

variable "asgs" {
  type        = map(string)
  default     = {}
  description = "Auto Scaling group names to monitor"
}

variable "load_balancers" {
  type        = map(string)
  default     = {}
  description = "ALB arn_suffix values to monitor"
}

variable "target_groups" {
  type = map(object({
    lb_arn_suffix = string
    tg_arn_suffix = string
  }))
  default     = {}
  description = "ALB target groups to monitor"
}

variable "web_acls" {
  type        = map(string)
  default     = {}
  description = "WAF web ACL names to monitor"
}

variable "rds_instances" {
  type        = map(string)
  default     = {}
  description = "RDS instance identifiers to monitor"
}

variable "waf_blocked_threshold" {
  default = 100
}

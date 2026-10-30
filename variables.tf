variable "region" {
  default = "eu-west-3"
}

variable "domain_name" {
  default = "everythingops.io"
}

variable "alert_email" {
  type        = string
  default     = ""
  description = "E-mail address that receives CloudWatch / AWS Backup alerts (confirm the SNS subscription e-mail)"
}

variable "db_deletion_protection" {
  type        = bool
  default     = true
  description = "Set to false before running the destroy pipeline"
}

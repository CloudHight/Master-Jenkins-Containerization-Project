
variable "domain" {
  description = "The domain name for our pet adoption project"
  type        = string
  default     = "everythingops.io"
}
variable "region" {
  default = "eu-west-3"
}
variable "alert_email" {
  type        = string
  default     = ""
  description = "E-mail address that receives CloudWatch / AWS Backup alerts"
}
variable "workload_name" {
  default     = "team-1"
  description = "Name prefix of the stack Jenkins deploys (scopes the deploy policy)"
}

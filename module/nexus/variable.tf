variable "name" {
  type        = string
  description = "A name prefix used for tagging and naming resources (e.g., team or environment name)."
}

variable "vpc" {
  type        = string
  description = "The ID of the VPC where resources like the security group will be created."
}

variable "subnets" {
  type        = list(string)
  description = "Public subnets (2 AZs) for the ALB"
}

variable "keypair" {}
variable "subnet_id" {}
variable "certificate" {}
variable "hosted_zone_id" {}
variable "domain_name" {}
variable "region" {}
variable "kms_key_arn" {}
variable "nexus_secret_arn" {}
variable "cw_config_param" {}

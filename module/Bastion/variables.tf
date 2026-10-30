variable "name" {}
variable "vpc" {}
variable "subnets" {
  type        = list(string)
  description = "List of subnet IDs for the bastion ASG"
}

variable "cw_config_param" {}
variable "keypair" {}
variable "region" {
  default = "eu-west-3"
}

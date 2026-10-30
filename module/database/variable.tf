variable "private_subnet1_id" {}
variable "private_subnet2_id" {}
variable "bastion-security-group" {}
variable "name" {}
variable "vpc-id" {}
variable "stage-security-group" {}
variable "prod-security-group" {}
variable "kms_key_arn" {}
variable "deletion_protection" {
  default = false
}

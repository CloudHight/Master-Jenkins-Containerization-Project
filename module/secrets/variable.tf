variable "name" {}
variable "kms_key_arn" {}
variable "ssh_private_key" {
  sensitive = true
}

# create aws provider
provider "aws" {
  region  = var.region
  profile = "default"
}

# State is stored locally (terraform.tfstate in this directory)

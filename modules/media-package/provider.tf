# Instantiated with providers = { aws = aws.ireland }: MediaPackage is not offered in af-south-1.
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}

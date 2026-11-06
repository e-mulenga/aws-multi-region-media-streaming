terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.60, < 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Partial configuration: bucket/key/region come from environments/<env>/backend.hcl.
  # State lives in the Landing Zone state bucket (see docs/landing-zone-integration.md).
  backend "s3" {}
}

locals {
  default_tags = {
    Project     = "aws-multi-region-media-streaming"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = var.owner
    CostCenter  = var.cost_center
  }
}

# Primary region: Africa (Cape Town).
provider "aws" {
  region = var.primary_region

  default_tags {
    tags = local.default_tags
  }
}

# Ireland: DR region AND the home for any service not available in af-south-1.
# Used by: MediaPackage (not offered in af-south-1), S3 replica bucket, DynamoDB replica,
# Aurora secondary cluster, DR backup vault.
# Deployed from eu-west-1 (service not available in af-south-1) - see docs/regional-availability.md.
provider "aws" {
  alias  = "ireland"
  region = var.dr_region

  default_tags {
    tags = local.default_tags
  }
}

# GLOBAL-SERVICE CONTROL PLANE ONLY (not a workload region and not an approved deployment region).
# CloudFront distributions, WAFv2 web ACLs with CLOUDFRONT scope, CloudFront-metric CloudWatch alarms
# and Route 53 health-check metrics are only addressable through us-east-1. The Landing Zone's
# CloudFront certificate is already there. No compute or data is placed here.
provider "aws" {
  alias  = "global_edge"
  region = "us-east-1"

  default_tags {
    tags = local.default_tags
  }
}

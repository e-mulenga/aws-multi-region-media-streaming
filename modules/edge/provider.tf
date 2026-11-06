# Instantiated with providers = { aws = aws.global_edge } (us-east-1): CloudFront, WAFv2 CLOUDFRONT scope,
# CloudFront metric alarms. Control plane only, no workloads. Route 53 records are global.
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

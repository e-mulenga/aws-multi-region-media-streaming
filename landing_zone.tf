# ============================================================
# Landing Zone consumption (source of truth).
# This stack never creates VPCs, subnets, NAT, ECR repositories, KMS keys, the Route 53 zone,
# ACM certificates, the platform SNS topic, GuardDuty, Security Hub, flow logs, state buckets or
# the GitHub OIDC provider. Everything below is READ from the Landing Zone's remote state.
# ============================================================

variable "landing_zone_state_bucket" {
  description = "S3 bucket holding the Landing Zone Terraform state."
  type        = string
}

variable "landing_zone_state_key" {
  description = "S3 key of the Landing Zone Terraform state."
  type        = string
}

variable "landing_zone_state_region" {
  description = "Region of the Landing Zone state bucket."
  type        = string
}

variable "expected_landing_zone_contract_version" {
  description = "Landing Zone contract_schema_version this stack was written against."
  type        = string
  default     = "2"
}

data "terraform_remote_state" "landing_zone" {
  backend = "s3"

  config = {
    bucket  = var.landing_zone_state_bucket
    key     = var.landing_zone_state_key
    region  = var.landing_zone_state_region
    encrypt = true
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  lz = data.terraform_remote_state.landing_zone.outputs

  lz_primary = local.lz.af_south_1
  lz_dr      = local.lz.eu_west_1

  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  name_prefix = "${var.workload_name}-${var.environment}"

  # Networking (used only by the optional Aurora cluster; Lambda is not VPC-attached, see ADR-004)
  primary_vpc_id          = local.lz_primary.vpc_id
  primary_vpc_cidr        = local.lz_primary.vpc_cidr_block
  primary_db_subnet_group = local.lz_primary.db_subnet_group
  dr_vpc_id               = local.lz_dr.vpc_id
  dr_vpc_cidr             = local.lz_dr.vpc_cidr_block
  dr_db_subnet_group      = local.lz_dr.db_subnet_group

  # DNS and TLS
  route53_zone_id     = local.lz.route53_zone_id
  route53_domain_name = local.lz.route53_domain_name
  cloudfront_cert_arn = local.lz.acm_cloudfront_certificate_arn
  alarm_topic_arn     = local.lz.monitoring_topic_arn

  # Key strategy: dev/test = AWS-managed keys, stage/prod = customer-managed keys from the Landing Zone.
  key_strategy    = local.lz.key_strategy
  use_cmk         = local.key_strategy != "aws-managed"
  shared_kms_keys = local.lz.shared_kms_keys

  kms_arn = {
    for purpose, domain in var.kms_key_domains :
    purpose => local.use_cmk ? try(local.shared_kms_keys[domain].arn, null) : null
  }

  # Keys for the DR region. The Landing Zone exports none, so for CMK environments they are supplied
  # as variables. In aws-managed mode they stay null (the AWS-managed key of the DR region is used).
  dr_kms_arn = {
    for purpose in ["s3", "dynamodb", "rds", "backup", "secrets"] :
    purpose => local.use_cmk ? lookup(var.dr_kms_key_arns, purpose, null) : null
  }
}

# ---- Guardrails: fail the plan when the Landing Zone does not fit ----
resource "terraform_data" "landing_zone_contract" {
  lifecycle {
    precondition {
      condition     = local.lz.contract_schema_version == var.expected_landing_zone_contract_version
      error_message = "Landing Zone contract_schema_version is '${local.lz.contract_schema_version}', expected '${var.expected_landing_zone_contract_version}'."
    }
    precondition {
      condition     = local.lz_primary.region == var.primary_region && local.lz_dr.region == var.dr_region
      error_message = "Landing Zone regions do not match primary_region/dr_region."
    }
    precondition {
      condition     = var.environment == "dev" || local.use_cmk
      error_message = "stage/prod require Customer Managed Keys, but the Landing Zone key_strategy is 'aws-managed'. This repo never creates keys: extend the Landing Zone export."
    }
    precondition {
      condition     = !local.use_cmk || alltrue([for purpose, arn in local.kms_arn : arn != null])
      error_message = "key_strategy is a CMK strategy but at least one shared_kms_keys domain mapped in var.kms_key_domains has no ARN in the Landing Zone export."
    }
    precondition {
      condition     = !local.use_cmk || alltrue([for purpose, arn in local.dr_kms_arn : arn != null])
      error_message = "CMK environments need an eu-west-1 key per purpose in var.dr_kms_key_arns (s3, dynamodb, rds, backup, secrets). The Landing Zone does not export DR-region keys."
    }
    precondition {
      condition     = local.route53_zone_id != null && local.cloudfront_cert_arn != null && local.alarm_topic_arn != null
      error_message = "Landing Zone is missing route53_zone_id, acm_cloudfront_certificate_arn or monitoring_topic_arn."
    }
  }
}

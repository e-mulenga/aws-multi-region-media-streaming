# Root stack. Everything shared (network, DNS, TLS, keys, alerts topic) is consumed from the
# Landing Zone via landing_zone.tf; this file wires the workload modules together.

locals {
  public_host = length(var.cloudfront_aliases) > 0 ? var.cloudfront_aliases[0] : ""
  dr_enabled  = var.enable_replication
}

module "storage" {
  source = "./modules/storage"

  providers = {
    aws         = aws
    aws.ireland = aws.ireland
  }

  name_prefix              = local.name_prefix
  environment              = var.environment
  account_id               = local.account_id
  kms_key_arn              = local.kms_arn["s3"]
  dr_kms_key_arn           = local.dr_kms_arn["s3"]
  enable_replication       = var.enable_replication
  processed_media_ia_days  = var.processed_media_ia_days
  archive_to_glacier_days  = var.archive_to_glacier_days
  delete_old_versions_days = var.delete_old_versions_days
  upload_cors_origins      = var.upload_cors_origins

  depends_on = [terraform_data.landing_zone_contract]
}

module "database" {
  source = "./modules/database"

  providers = {
    aws         = aws
    aws.ireland = aws.ireland
  }

  name_prefix             = local.name_prefix
  environment             = var.environment
  dynamodb_kms_key_arn    = local.kms_arn["dynamodb"]
  dr_dynamodb_kms_key_arn = local.dr_kms_arn["dynamodb"]
  rds_kms_key_arn         = local.kms_arn["rds"]
  dr_rds_kms_key_arn      = local.dr_kms_arn["rds"]
  secrets_kms_key_arn     = local.kms_arn["secrets"]
  dynamodb_billing_mode   = var.dynamodb_billing_mode
  enable_dynamodb_replica = var.enable_dynamodb_replica
  enable_aurora           = var.enable_aurora
  aurora_engine_version   = var.aurora_engine_version
  aurora_instance_class   = var.aurora_instance_class
  aurora_db_name          = var.aurora_db_name
  primary_vpc_id          = local.primary_vpc_id
  primary_vpc_cidr        = local.primary_vpc_cidr
  primary_db_subnet_group = local.primary_db_subnet_group
  dr_vpc_id               = local.dr_vpc_id
  dr_vpc_cidr             = local.dr_vpc_cidr
  dr_db_subnet_group      = local.dr_db_subnet_group

  depends_on = [terraform_data.landing_zone_contract]
}

module "media_convert" {
  source = "./modules/media-convert"

  name_prefix          = local.name_prefix
  ingestion_bucket_arn = module.storage.ingestion_bucket_arn
  processed_bucket_arn = module.storage.processed_bucket_arn
  s3_kms_key_arn       = local.kms_arn["s3"]
  alarm_topic_arn      = local.alarm_topic_arn
}

# MediaPackage: not available in af-south-1 -> deployed from eu-west-1 (service not available in af-south-1).
module "media_package" {
  count  = var.enable_media_package ? 1 : 0
  source = "./modules/media-package"

  providers = {
    aws = aws.ireland
  }

  name_prefix          = local.name_prefix
  kms_key_arn          = local.dr_kms_arn["secrets"]
  hls_segment_duration = var.hls_segment_duration
}

module "api" {
  source = "./modules/api"

  name_prefix          = local.name_prefix
  environment          = var.environment
  content_table_name   = module.database.content_table_name
  content_table_arn    = module.database.content_table_arn
  analytics_table_name = module.database.analytics_table_name
  analytics_table_arn  = module.database.analytics_table_arn
  dynamodb_kms_key_arn = local.kms_arn["dynamodb"]
  lambda_kms_key_arn   = local.kms_arn["lambda"]
  logs_kms_key_arn     = local.kms_arn["logs"]
  public_base_host     = local.public_host
  enable_xray          = var.enable_xray
  log_retention_days   = var.log_retention_days
  alarm_topic_arn      = local.alarm_topic_arn
  jwt_issuer           = var.jwt_issuer
  jwt_audience         = var.jwt_audience
}

module "workflow" {
  source = "./modules/workflow"

  name_prefix            = local.name_prefix
  partition              = local.partition
  region                 = var.primary_region
  account_id             = local.account_id
  environment            = var.environment
  ingestion_bucket_id    = module.storage.ingestion_bucket_id
  ingestion_bucket_arn   = module.storage.ingestion_bucket_arn
  processed_bucket_id    = module.storage.processed_bucket_id
  content_table_name     = module.database.content_table_name
  content_table_arn      = module.database.content_table_arn
  mediaconvert_queue_arn = module.media_convert.queue_arn
  mediaconvert_role_arn  = module.media_convert.role_arn
  alarm_topic_arn        = local.alarm_topic_arn
  s3_kms_key_arn         = local.kms_arn["s3"]
  dynamodb_kms_key_arn   = local.kms_arn["dynamodb"]
  lambda_kms_key_arn     = local.kms_arn["lambda"]
  logs_kms_key_arn       = local.kms_arn["logs"]
  enable_xray            = var.enable_xray
  log_retention_days     = var.log_retention_days
}

# CloudFront + WAF: global-service control plane in us-east-1 (see provider.tf).
module "edge" {
  source = "./modules/edge"

  providers = {
    aws = aws.global_edge
  }

  name_prefix                  = local.name_prefix
  aliases                      = var.cloudfront_aliases
  certificate_arn              = local.cloudfront_cert_arn
  route53_zone_id              = local.route53_zone_id
  price_class                  = var.cloudfront_price_class
  allowed_countries            = var.allowed_countries
  waf_rate_limit               = var.waf_rate_limit
  log_retention_days           = var.log_retention_days
  enable_shield_advanced       = var.enable_shield_advanced
  logging_bucket_domain        = var.enable_cloudfront_logging ? "${local.lz.access_logs_bucket_name}.s3.amazonaws.com" : null
  processed_bucket_domain      = module.storage.processed_bucket_regional_domain_name
  processed_dr_bucket_domain   = module.storage.processed_dr_bucket_regional_domain_name
  enable_origin_shield         = var.enable_origin_shield
  origin_shield_region         = var.origin_shield_region
  api_domain                   = module.api.api_domain
  media_package_domain         = var.enable_media_package ? module.media_package[0].origin_domain : null
  media_package_cdn_identifier = var.enable_media_package ? module.media_package[0].cdn_identifier : null
  alert_emails                 = var.edge_alert_emails
}

# Processed-bucket policy: TLS only + read by this distribution through OAC. Kept at root level
# because it needs both the bucket and the distribution ARN.
data "aws_iam_policy_document" "processed" {
  statement {
    sid       = "DenyNonTLS"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [module.storage.processed_bucket_arn, "${module.storage.processed_bucket_arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid       = "AllowCloudFrontOAC"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${module.storage.processed_bucket_arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [module.edge.distribution_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "processed" {
  bucket = module.storage.processed_bucket_id
  policy = data.aws_iam_policy_document.processed.json
}

data "aws_iam_policy_document" "processed_dr" {
  count = local.dr_enabled ? 1 : 0

  statement {
    sid       = "DenyNonTLS"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [module.storage.processed_dr_bucket_arn, "${module.storage.processed_dr_bucket_arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid       = "AllowCloudFrontOAC"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${module.storage.processed_dr_bucket_arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [module.edge.distribution_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "processed_dr" {
  count    = local.dr_enabled ? 1 : 0
  provider = aws.ireland

  bucket = module.storage.processed_dr_bucket_id
  policy = data.aws_iam_policy_document.processed_dr[0].json
}

module "monitoring" {
  source = "./modules/monitoring"

  name_prefix                = local.name_prefix
  environment                = var.environment
  region                     = var.primary_region
  alarm_topic_arn            = local.alarm_topic_arn
  cloudfront_distribution_id = module.edge.distribution_id
  workflow_state_machine_arn = module.workflow.state_machine_arn
  mediaconvert_queue_arn     = module.media_convert.queue_arn
  api_id                     = module.api.api_id
}

module "disaster_recovery" {
  source = "./modules/disaster-recovery"

  providers = {
    aws             = aws
    aws.ireland     = aws.ireland
    aws.global_edge = aws.global_edge
  }

  name_prefix           = local.name_prefix
  partition             = local.partition
  environment           = var.environment
  api_domain            = module.api.api_domain
  edge_alerts_topic_arn = module.edge.edge_alerts_topic_arn
  backup_kms_key_arn    = local.kms_arn["backup"]
  dr_backup_kms_key_arn = local.dr_kms_arn["backup"]

  backup_resource_arns = compact([
    module.database.content_table_arn,
    module.storage.processed_bucket_arn,
    module.storage.archive_bucket_arn,
    module.database.aurora_primary_cluster_arn,
  ])
}

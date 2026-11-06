variable "workload_name" {
  description = "Workload name prefix used in resource names."
  type        = string
  default     = "media-streaming"
}

variable "environment" {
  description = "dev, stage or prod."
  type        = string

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "environment must be dev, stage or prod."
  }
}

variable "owner" {
  description = "Owning team (tag)."
  type        = string
}

variable "cost_center" {
  description = "Cost centre (tag)."
  type        = string
}

variable "primary_region" {
  description = "Primary region (Cape Town)."
  type        = string
  default     = "af-south-1"

  validation {
    condition     = var.primary_region == "af-south-1"
    error_message = "Approved primary region is af-south-1."
  }
}

variable "dr_region" {
  description = "DR region (Ireland). Also where services unavailable in af-south-1 are deployed."
  type        = string
  default     = "eu-west-1"

  validation {
    condition     = var.dr_region == "eu-west-1"
    error_message = "Approved DR region is eu-west-1."
  }
}

# ---- Encryption ----
variable "kms_key_domains" {
  description = "Purpose => Landing Zone shared_kms_keys domain. Used only when key_strategy is not aws-managed. ASSUMPTION: the Landing Zone exports ai, analytics, backup, rds and s3 only, so dynamodb maps to analytics and secrets to rds."
  type        = map(string)
  default = {
    s3       = "s3"
    dynamodb = "analytics"
    rds      = "rds"
    backup   = "backup"
    logs     = "s3"
    secrets  = "rds"
    lambda   = "s3"
  }
}

variable "dr_kms_key_arns" {
  description = "eu-west-1 CMK ARNs by purpose (s3, dynamodb, rds, backup, secrets). Required for stage/prod because the Landing Zone exports no DR-region keys. Ignored in dev."
  type        = map(string)
  default     = {}
}

# ---- Edge ----
variable "cloudfront_aliases" {
  description = "Hostnames served by CloudFront, for example [\"media.emulenga.com\"]. They must be covered by the Landing Zone us-east-1 certificate. Empty = default *.cloudfront.net domain."
  type        = list(string)
  default     = []
}

variable "cloudfront_price_class" {
  description = "PriceClass_All is required for the best edge coverage in Africa; PriceClass_100/200 exclude African edge locations."
  type        = string
  default     = "PriceClass_All"
}

variable "enable_origin_shield" {
  description = "Enable CloudFront Origin Shield on the S3 origin."
  type        = bool
  default     = false
}

variable "origin_shield_region" {
  description = "Origin Shield region. Must be a region where Origin Shield is offered; verify before enabling."
  type        = string
  default     = "eu-west-1"
}

variable "allowed_countries" {
  description = "ISO country codes allowed by CloudFront geo restriction. Empty = no restriction."
  type        = list(string)
  default     = []
}

variable "waf_rate_limit" {
  description = "Requests per 5 minutes per IP before WAF blocks."
  type        = number
  default     = 2000
}

variable "enable_shield_advanced" {
  description = "Create an AWS Shield Advanced protection for the distribution. Requires an existing Shield Advanced subscription (flat monthly fee)."
  type        = bool
  default     = false
}

variable "enable_cloudfront_logging" {
  description = "Send CloudFront standard logs to the Landing Zone access-logs bucket. The bucket must have ACLs enabled and grant CloudFront log delivery; the Landing Zone does not guarantee that."
  type        = bool
  default     = false
}

variable "edge_alert_emails" {
  description = "E-mail addresses subscribed to the us-east-1 edge alert topic (CloudFront and Route 53 alarms cannot use the af-south-1 Landing Zone topic)."
  type        = list(string)
  default     = []
}

# ---- Media pipeline ----
variable "enable_media_package" {
  description = "Create MediaPackage live channel + endpoint (deployed from eu-west-1: not available in af-south-1)."
  type        = bool
  default     = false
}

variable "hls_segment_duration" {
  description = "MediaPackage HLS segment duration (seconds)."
  type        = number
  default     = 6
}

variable "enable_xray" {
  description = "Enable X-Ray active tracing on Lambda and Step Functions."
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention."
  type        = number
  default     = 90
}

# ---- Data ----
variable "enable_replication" {
  description = "S3 cross-region replication of the processed bucket to eu-west-1."
  type        = bool
  default     = true
}

variable "enable_dynamodb_replica" {
  description = "DynamoDB global-table replica of the content-metadata table in eu-west-1. Support for af-south-1 global tables was not verified, see docs/regional-availability.md."
  type        = bool
  default     = true
}

variable "dynamodb_billing_mode" {
  description = "PAY_PER_REQUEST or PROVISIONED."
  type        = string
  default     = "PAY_PER_REQUEST"
}

variable "enable_aurora" {
  description = "Create the Aurora PostgreSQL global database (af-south-1 primary, eu-west-1 secondary). No code path uses it yet; default off."
  type        = bool
  default     = false
}

variable "aurora_engine_version" {
  description = "Aurora PostgreSQL version. Cape Town supports global databases from 16.1; verify the exact minor version in your account."
  type        = string
  default     = "16.4"
}

variable "aurora_instance_class" {
  description = "Instance class. Global databases need a memory-optimised class."
  type        = string
  default     = "db.r6g.large"
}

variable "aurora_db_name" {
  description = "Initial database name."
  type        = string
  default     = "catalogue"
}

variable "processed_media_ia_days" {
  description = "Days before processed media moves to STANDARD_IA."
  type        = number
  default     = 30
}

variable "archive_to_glacier_days" {
  description = "Days before processed media moves to GLACIER and archive to DEEP_ARCHIVE."
  type        = number
  default     = 90
}

variable "delete_old_versions_days" {
  description = "Days to keep noncurrent S3 versions."
  type        = number
  default     = 30
}

variable "upload_cors_origins" {
  description = "Browser origins allowed to PUT to the ingestion bucket with pre-signed URLs. Empty = no CORS rule."
  type        = list(string)
  default     = []
}

# ---- API ----
variable "jwt_issuer" {
  description = "OIDC issuer URL for the API JWT authorizer. Empty = write routes are NOT authenticated (acceptable for dev only)."
  type        = string
  default     = ""
}

variable "jwt_audience" {
  description = "Audience(s) accepted by the JWT authorizer."
  type        = list(string)
  default     = []
}

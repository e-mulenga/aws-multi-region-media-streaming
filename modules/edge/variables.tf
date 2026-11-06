variable "name_prefix" {
  type        = string
  description = "Resource name prefix."
}

variable "aliases" {
  type        = list(string)
  description = "CloudFront alias hostnames."
  default     = []
}

variable "certificate_arn" {
  type        = string
  description = "Landing Zone us-east-1 ACM certificate (used only when aliases are set)."
}

variable "route53_zone_id" {
  type        = string
  description = "Landing Zone Route 53 zone."
}

variable "price_class" {
  type        = string
  description = "CloudFront price class."
  default     = "PriceClass_All"
}

variable "allowed_countries" {
  type        = list(string)
  description = "Geo whitelist. Empty = none."
  default     = []
}

variable "waf_rate_limit" {
  type        = number
  description = "Requests per 5 minutes per IP."
  default     = 2000
}

variable "log_retention_days" {
  type        = number
  description = "WAF log retention."
  default     = 90
}

variable "enable_shield_advanced" {
  type        = bool
  description = "Shield Advanced protection."
  default     = false
}

variable "logging_bucket_domain" {
  type        = string
  description = "S3 domain of the Landing Zone access-logs bucket. Null = no CloudFront logging."
  default     = null
}

variable "processed_bucket_domain" {
  type        = string
  description = "Regional domain of the af-south-1 processed bucket."
}

variable "processed_dr_bucket_domain" {
  type        = string
  description = "Regional domain of the eu-west-1 replica bucket. Null = no failover origin group."
  default     = null
}

variable "enable_origin_shield" {
  type        = bool
  description = "Origin Shield on the S3 origin."
  default     = false
}

variable "origin_shield_region" {
  type        = string
  description = "Origin Shield region."
  default     = "eu-west-1"
}

variable "api_domain" {
  type        = string
  description = "execute-api hostname of the HTTP API."
}

variable "media_package_domain" {
  type        = string
  description = "MediaPackage origin hostname. Null = no live behaviour."
  default     = null
}

variable "media_package_cdn_identifier" {
  type        = string
  description = "Shared CDN authorization secret."
  default     = null
  sensitive   = true
}

variable "alert_emails" {
  type        = list(string)
  description = "Subscribers of the edge alert topic."
  default     = []
}

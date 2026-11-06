variable "name_prefix" {
  type        = string
  description = "Resource name prefix."
}

variable "content_table_name" {
  type        = string
  description = "Content table name."
}

variable "content_table_arn" {
  type        = string
  description = "Content table ARN."
}

variable "analytics_table_name" {
  type        = string
  description = "Analytics table name."
}

variable "analytics_table_arn" {
  type        = string
  description = "Analytics table ARN."
}

variable "dynamodb_kms_key_arn" {
  type        = string
  description = "CMK for the tables (Decrypt/GenerateDataKey). Null = AWS-managed."
  default     = null
}

variable "lambda_kms_key_arn" {
  type        = string
  description = "CMK for Lambda environment variables. Null = AWS-managed."
  default     = null
}

variable "logs_kms_key_arn" {
  type        = string
  description = "CMK for log groups. Null = CloudWatch default encryption."
  default     = null
}

variable "public_base_host" {
  type        = string
  description = "Public hostname used to build playback URLs. Empty = relative URLs."
  default     = ""
}

variable "environment" {
  type        = string
  description = "dev, stage or prod."
}

variable "enable_xray" {
  type        = bool
  description = "Active tracing."
  default     = true
}

variable "log_retention_days" {
  type        = number
  description = "Log retention."
  default     = 90
}

variable "alarm_topic_arn" {
  type        = string
  description = "Landing Zone SNS topic."
}

variable "jwt_issuer" {
  type        = string
  description = "OIDC issuer for the JWT authorizer. Empty = no authorizer."
  default     = ""
}

variable "jwt_audience" {
  type        = list(string)
  description = "JWT audiences."
  default     = []
}

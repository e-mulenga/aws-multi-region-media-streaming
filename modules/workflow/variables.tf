variable "name_prefix" {
  type        = string
  description = "Resource name prefix."
}

variable "partition" {
  type        = string
  description = "AWS partition."
  default     = "aws"
}

variable "region" {
  type        = string
  description = "Deployment region."
}

variable "account_id" {
  type        = string
  description = "Account ID."
}

variable "environment" {
  type        = string
  description = "dev, stage or prod."
}

variable "ingestion_bucket_id" {
  type        = string
  description = "Ingestion bucket name."
}

variable "ingestion_bucket_arn" {
  type        = string
  description = "Ingestion bucket ARN."
}

variable "processed_bucket_id" {
  type        = string
  description = "Processed bucket name."
}

variable "content_table_name" {
  type        = string
  description = "Content table name."
}

variable "content_table_arn" {
  type        = string
  description = "Content table ARN."
}

variable "mediaconvert_queue_arn" {
  type        = string
  description = "MediaConvert queue ARN."
}

variable "mediaconvert_role_arn" {
  type        = string
  description = "MediaConvert service role ARN."
}

variable "alarm_topic_arn" {
  type        = string
  description = "Landing Zone SNS topic (notifications)."
}

variable "s3_kms_key_arn" {
  type        = string
  description = "CMK for the buckets. Null = SSE-S3."
  default     = null
}

variable "dynamodb_kms_key_arn" {
  type        = string
  description = "CMK for the tables. Null = AWS-managed."
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

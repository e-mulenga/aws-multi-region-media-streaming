variable "name_prefix" {
  type        = string
  description = "Resource name prefix."
}

variable "ingestion_bucket_arn" {
  type        = string
  description = "Source bucket ARN."
}

variable "processed_bucket_arn" {
  type        = string
  description = "Output bucket ARN."
}

variable "s3_kms_key_arn" {
  type        = string
  description = "CMK protecting both buckets. Null = SSE-S3."
  default     = null
}

variable "alarm_topic_arn" {
  type        = string
  description = "Landing Zone SNS topic for alarms."
}

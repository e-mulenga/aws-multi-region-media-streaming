variable "name_prefix" {
  type        = string
  description = "Resource name prefix."
}

variable "environment" {
  type        = string
  description = "dev, stage or prod."
}

variable "account_id" {
  type        = string
  description = "Account ID (bucket-name uniqueness suffix)."
}

variable "kms_key_arn" {
  type        = string
  description = "af-south-1 CMK for S3. Null = SSE-S3 (AWS-managed)."
  default     = null
}

variable "dr_kms_key_arn" {
  type        = string
  description = "eu-west-1 CMK for the replica bucket. Null = SSE-S3."
  default     = null
}

variable "enable_replication" {
  type        = bool
  description = "Replicate the processed bucket to eu-west-1."
  default     = true
}

variable "processed_media_ia_days" {
  type        = number
  description = "Days before processed media moves to STANDARD_IA."
  default     = 30
}

variable "archive_to_glacier_days" {
  type        = number
  description = "Days before processed media moves to GLACIER and archive to DEEP_ARCHIVE."
  default     = 180
}

variable "delete_old_versions_days" {
  type        = number
  description = "Days to keep noncurrent versions."
  default     = 30
}

variable "upload_cors_origins" {
  type        = list(string)
  description = "Origins allowed to upload with pre-signed URLs. Empty = no CORS rule."
  default     = []
}

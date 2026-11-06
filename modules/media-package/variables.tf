variable "name_prefix" {
  type        = string
  description = "Resource name prefix."
}

variable "kms_key_arn" {
  type        = string
  description = "eu-west-1 CMK for the CDN secret. Null = AWS-managed key."
  default     = null
}

variable "hls_segment_duration" {
  type        = number
  description = "HLS segment duration in seconds."
  default     = 6
}

variable "name_prefix" {
  type        = string
  description = "Resource name prefix."
}

variable "partition" {
  type        = string
  description = "AWS partition."
  default     = "aws"
}

variable "environment" {
  type        = string
  description = "dev, stage or prod."
}

variable "api_domain" {
  type        = string
  description = "execute-api hostname probed by the health check."
}

variable "edge_alerts_topic_arn" {
  type        = string
  description = "us-east-1 topic for the Route 53 health-check alarm."
}

variable "backup_kms_key_arn" {
  type        = string
  description = "af-south-1 backup CMK. Null = AWS-managed backup key."
  default     = null
}

variable "dr_backup_kms_key_arn" {
  type        = string
  description = "eu-west-1 backup CMK. Null = AWS-managed backup key."
  default     = null
}

variable "backup_resource_arns" {
  type        = list(string)
  description = "Resources to back up (DynamoDB tables, S3 buckets, Aurora)."
}

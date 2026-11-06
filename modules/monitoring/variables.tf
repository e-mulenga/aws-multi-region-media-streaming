variable "name_prefix" {
  type        = string
  description = "Resource name prefix."
}

variable "environment" {
  type        = string
  description = "dev, stage or prod."
}

variable "region" {
  type        = string
  description = "Dashboard region."
}

variable "alarm_topic_arn" {
  type        = string
  description = "Landing Zone SNS topic."
}

variable "cloudfront_distribution_id" {
  type        = string
  description = "CloudFront distribution ID."
}

variable "workflow_state_machine_arn" {
  type        = string
  description = "State machine ARN."
}

variable "mediaconvert_queue_arn" {
  type        = string
  description = "MediaConvert queue ARN."
}

variable "api_id" {
  type        = string
  description = "HTTP API ID."
}

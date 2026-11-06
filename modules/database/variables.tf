variable "name_prefix" {
  type        = string
  description = "Resource name prefix."
}

variable "environment" {
  type        = string
  description = "dev, stage or prod."
}

variable "dynamodb_kms_key_arn" {
  type        = string
  description = "af-south-1 CMK for DynamoDB. Null = AWS-managed key."
  default     = null
}

variable "dr_dynamodb_kms_key_arn" {
  type        = string
  description = "eu-west-1 CMK for the replica. Null = AWS-managed key."
  default     = null
}

variable "rds_kms_key_arn" {
  type        = string
  description = "af-south-1 CMK for Aurora. Null = AWS-managed key."
  default     = null
}

variable "dr_rds_kms_key_arn" {
  type        = string
  description = "eu-west-1 CMK for the Aurora secondary. Null = AWS-managed key."
  default     = null
}

variable "secrets_kms_key_arn" {
  type        = string
  description = "CMK for the Aurora master-user secret. Null = AWS-managed key."
  default     = null
}

variable "dynamodb_billing_mode" {
  type        = string
  description = "PAY_PER_REQUEST or PROVISIONED."
  default     = "PAY_PER_REQUEST"
}

variable "enable_dynamodb_replica" {
  type        = bool
  description = "Global-table replica in eu-west-1."
  default     = true
}

variable "enable_aurora" {
  type        = bool
  description = "Create the Aurora global database."
  default     = false
}

variable "aurora_engine_version" {
  type        = string
  description = "Aurora PostgreSQL version."
  default     = "16.4"
}

variable "aurora_instance_class" {
  type        = string
  description = "Instance class."
  default     = "db.r6g.large"
}

variable "aurora_db_name" {
  type        = string
  description = "Initial database name."
  default     = "catalogue"
}

variable "primary_vpc_id" {
  type        = string
  description = "Landing Zone af-south-1 VPC."
}

variable "primary_vpc_cidr" {
  type        = string
  description = "Landing Zone af-south-1 VPC CIDR."
}

variable "primary_db_subnet_group" {
  type        = string
  description = "Landing Zone af-south-1 DB subnet group."
}

variable "dr_vpc_id" {
  type        = string
  description = "Landing Zone eu-west-1 VPC."
}

variable "dr_vpc_cidr" {
  type        = string
  description = "Landing Zone eu-west-1 VPC CIDR."
}

variable "dr_db_subnet_group" {
  type        = string
  description = "Landing Zone eu-west-1 DB subnet group."
}

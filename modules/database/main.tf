# Module: database - DynamoDB tables (+ eu-west-1 replica) and the optional Aurora PostgreSQL global database.
# VPCs, subnets and DB subnet groups come from the Landing Zone; only security groups are created here.

locals {
  prod       = var.environment == "prod"
  ddb_billed = var.dynamodb_billing_mode
}

resource "aws_dynamodb_table" "content_metadata" {
  name             = "${var.name_prefix}-content-metadata"
  billing_mode     = local.ddb_billed
  hash_key         = "content_id"
  range_key        = "version"
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  attribute {
    name = "content_id"
    type = "S"
  }

  attribute {
    name = "version"
    type = "N"
  }

  attribute {
    name = "status"
    type = "S"
  }

  attribute {
    name = "created_at"
    type = "S"
  }

  global_secondary_index {
    name            = "status-created-index"
    hash_key        = "status"
    range_key       = "created_at"
    projection_type = "ALL"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.dynamodb_kms_key_arn
  }

  point_in_time_recovery {
    enabled = true
  }

  deletion_protection_enabled = local.prod
}

resource "aws_dynamodb_table_replica" "content_metadata" {
  count    = var.enable_dynamodb_replica ? 1 : 0
  provider = aws.ireland

  global_table_arn = aws_dynamodb_table.content_metadata.arn
  kms_key_arn      = var.dr_dynamodb_kms_key_arn

  point_in_time_recovery = true
}

resource "aws_dynamodb_table" "viewer_analytics" {
  name         = "${var.name_prefix}-viewer-analytics"
  billing_mode = local.ddb_billed
  hash_key     = "event_id"
  range_key    = "timestamp"

  attribute {
    name = "event_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  attribute {
    name = "content_id"
    type = "S"
  }

  global_secondary_index {
    name            = "content-analytics-index"
    hash_key        = "content_id"
    range_key       = "timestamp"
    projection_type = "ALL"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.dynamodb_kms_key_arn
  }

  point_in_time_recovery {
    enabled = true
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  deletion_protection_enabled = local.prod
}

# ---- Aurora global database (optional) ----
resource "aws_rds_global_cluster" "main" {
  count = var.enable_aurora ? 1 : 0

  global_cluster_identifier = "${var.name_prefix}-global"
  engine                    = "aurora-postgresql"
  engine_version            = var.aurora_engine_version
  database_name             = var.aurora_db_name
  storage_encrypted         = true
  deletion_protection       = local.prod
}

resource "aws_security_group" "aurora_primary" {
  count = var.enable_aurora ? 1 : 0

  name        = "${var.name_prefix}-aurora-primary"
  description = "Aurora PostgreSQL (af-south-1): 5432 from the Landing Zone VPC CIDR only"
  vpc_id      = var.primary_vpc_id

  ingress {
    description = "PostgreSQL from the VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.primary_vpc_cidr]
  }
}

resource "aws_security_group" "aurora_dr" {
  count    = var.enable_aurora ? 1 : 0
  provider = aws.ireland

  name        = "${var.name_prefix}-aurora-dr"
  description = "Aurora PostgreSQL (eu-west-1): 5432 from the Landing Zone VPC CIDR only"
  vpc_id      = var.dr_vpc_id

  ingress {
    description = "PostgreSQL from the VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.dr_vpc_cidr]
  }
}

resource "aws_rds_cluster" "primary" {
  count = var.enable_aurora ? 1 : 0

  cluster_identifier                  = "${var.name_prefix}-aurora-primary"
  engine                              = "aurora-postgresql"
  engine_version                      = var.aurora_engine_version
  global_cluster_identifier           = aws_rds_global_cluster.main[0].id
  database_name                       = var.aurora_db_name
  master_username                     = "catalogue_admin"
  manage_master_user_password         = true
  master_user_secret_kms_key_id       = var.secrets_kms_key_arn
  db_subnet_group_name                = var.primary_db_subnet_group
  vpc_security_group_ids              = [aws_security_group.aurora_primary[0].id]
  storage_encrypted                   = true
  kms_key_id                          = var.rds_kms_key_arn
  deletion_protection                 = local.prod
  skip_final_snapshot                 = !local.prod
  final_snapshot_identifier           = local.prod ? "${var.name_prefix}-aurora-final" : null
  backup_retention_period             = local.prod ? 35 : 7
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  iam_database_authentication_enabled = true
}

resource "aws_rds_cluster_instance" "primary" {
  count = var.enable_aurora ? (local.prod ? 2 : 1) : 0

  identifier          = "${var.name_prefix}-aurora-primary-${count.index + 1}"
  cluster_identifier  = aws_rds_cluster.primary[0].id
  engine              = "aurora-postgresql"
  engine_version      = var.aurora_engine_version
  instance_class      = var.aurora_instance_class
  publicly_accessible = false
}

resource "aws_rds_cluster" "secondary" {
  count    = var.enable_aurora ? 1 : 0
  provider = aws.ireland

  cluster_identifier        = "${var.name_prefix}-aurora-dr"
  engine                    = "aurora-postgresql"
  engine_version            = var.aurora_engine_version
  global_cluster_identifier = aws_rds_global_cluster.main[0].id
  db_subnet_group_name      = var.dr_db_subnet_group
  vpc_security_group_ids    = [aws_security_group.aurora_dr[0].id]
  storage_encrypted         = true
  kms_key_id                = var.dr_rds_kms_key_arn
  deletion_protection       = local.prod
  skip_final_snapshot       = true

  depends_on = [aws_rds_cluster_instance.primary]
}

resource "aws_rds_cluster_instance" "secondary" {
  count    = var.enable_aurora ? 1 : 0
  provider = aws.ireland

  identifier          = "${var.name_prefix}-aurora-dr-1"
  cluster_identifier  = aws_rds_cluster.secondary[0].id
  engine              = "aurora-postgresql"
  engine_version      = var.aurora_engine_version
  instance_class      = var.aurora_instance_class
  publicly_accessible = false
}

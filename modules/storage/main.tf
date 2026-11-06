# Module: storage - ingestion, processed and archive buckets in af-south-1 plus the eu-west-1 replica.
# Server-access/CloudFront logging buckets are NOT created: the Landing Zone owns log buckets
# (they are in us-east-1, so same-region S3 server access logging is not possible, see docs).
# The processed-bucket policy (TLS-only + CloudFront OAC) is attached from the root module because
# it needs the distribution ARN.

locals {
  buckets   = toset(["ingestion", "processed", "archive"])
  sse_algo  = var.kms_key_arn == null ? "AES256" : "aws:kms"
  dr_algo   = var.dr_kms_key_arn == null ? "AES256" : "aws:kms"
  force_del = var.environment == "dev"
}

resource "aws_s3_bucket" "this" {
  for_each = local.buckets

  bucket        = "${var.name_prefix}-${each.key}-${var.account_id}"
  force_destroy = each.key == "archive" ? false : local.force_del

  tags = { Purpose = "media-${each.key}" }
}

resource "aws_s3_bucket_versioning" "this" {
  for_each = local.buckets

  bucket = aws_s3_bucket.this[each.key].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = local.buckets

  bucket = aws_s3_bucket.this[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = local.sse_algo
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = var.kms_key_arn != null
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = local.buckets

  bucket                  = aws_s3_bucket.this[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "this" {
  for_each = local.buckets

  bucket = aws_s3_bucket.this[each.key].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# ---- TLS-only policies (processed bucket policy is attached by the root module) ----
resource "aws_s3_bucket_policy" "tls_only" {
  for_each = toset(["ingestion", "archive"])

  bucket = aws_s3_bucket.this[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyNonTLS"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.this[each.key].arn, "${aws_s3_bucket.this[each.key].arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.this]
}

# ---- Lifecycle ----
resource "aws_s3_bucket_lifecycle_configuration" "ingestion" {
  bucket = aws_s3_bucket.this["ingestion"].id

  rule {
    id     = "ingestion-lifecycle"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = 365
    }

    noncurrent_version_expiration {
      noncurrent_days = var.delete_old_versions_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

resource "aws_s3_bucket_lifecycle_configuration" "processed" {
  bucket = aws_s3_bucket.this["processed"].id

  rule {
    id     = "processed-tiering"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    transition {
      days          = var.processed_media_ia_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.archive_to_glacier_days
      storage_class = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = var.delete_old_versions_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

resource "aws_s3_bucket_lifecycle_configuration" "archive" {
  bucket = aws_s3_bucket.this["archive"].id

  rule {
    id     = "deep-archive"
    status = "Enabled"

    filter {}

    transition {
      days          = 1
      storage_class = "GLACIER"
    }

    transition {
      days          = var.archive_to_glacier_days
      storage_class = "DEEP_ARCHIVE"
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

resource "aws_s3_bucket_cors_configuration" "ingestion" {
  count = length(var.upload_cors_origins) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this["ingestion"].id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST"]
    allowed_origins = var.upload_cors_origins
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# New objects go to EventBridge, which starts the Step Functions workflow.
resource "aws_s3_bucket_notification" "ingestion" {
  bucket      = aws_s3_bucket.this["ingestion"].id
  eventbridge = true
}

# ---- eu-west-1 replica of the processed bucket (DR) ----
resource "aws_s3_bucket" "processed_dr" {
  count    = var.enable_replication ? 1 : 0
  provider = aws.ireland

  bucket        = "${var.name_prefix}-processed-dr-${var.account_id}"
  force_destroy = local.force_del

  tags = { Purpose = "media-processed-replica" }
}

resource "aws_s3_bucket_versioning" "processed_dr" {
  count    = var.enable_replication ? 1 : 0
  provider = aws.ireland

  bucket = aws_s3_bucket.processed_dr[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "processed_dr" {
  count    = var.enable_replication ? 1 : 0
  provider = aws.ireland

  bucket = aws_s3_bucket.processed_dr[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = local.dr_algo
      kms_master_key_id = var.dr_kms_key_arn
    }
    bucket_key_enabled = var.dr_kms_key_arn != null
  }
}

resource "aws_s3_bucket_public_access_block" "processed_dr" {
  count    = var.enable_replication ? 1 : 0
  provider = aws.ireland

  bucket                  = aws_s3_bucket.processed_dr[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "processed_dr" {
  count    = var.enable_replication ? 1 : 0
  provider = aws.ireland

  bucket = aws_s3_bucket.processed_dr[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# ---- Replication ----
resource "aws_iam_role" "replication" {
  count = var.enable_replication ? 1 : 0

  name = "${var.name_prefix}-s3-replication"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "replication" {
  count = var.enable_replication ? 1 : 0

  name = "s3-replication"
  role = aws_iam_role.replication[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Effect   = "Allow"
          Action   = ["s3:GetReplicationConfiguration", "s3:ListBucket"]
          Resource = [aws_s3_bucket.this["processed"].arn]
        },
        {
          Effect   = "Allow"
          Action   = ["s3:GetObjectVersionForReplication", "s3:GetObjectVersionAcl", "s3:GetObjectVersionTagging"]
          Resource = ["${aws_s3_bucket.this["processed"].arn}/*"]
        },
        {
          Effect   = "Allow"
          Action   = ["s3:ReplicateObject", "s3:ReplicateDelete", "s3:ReplicateTags"]
          Resource = ["${aws_s3_bucket.processed_dr[0].arn}/*"]
        }
      ],
      var.kms_key_arn == null ? [] : [{
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = [var.kms_key_arn]
      }],
      var.dr_kms_key_arn == null ? [] : [{
        Effect   = "Allow"
        Action   = ["kms:Encrypt", "kms:GenerateDataKey"]
        Resource = [var.dr_kms_key_arn]
      }]
    )
  })
}

resource "aws_s3_bucket_replication_configuration" "processed" {
  count = var.enable_replication ? 1 : 0

  bucket = aws_s3_bucket.this["processed"].id
  role   = aws_iam_role.replication[0].arn

  rule {
    id     = "replicate-processed-media"
    status = "Enabled"

    filter {}

    delete_marker_replication {
      status = "Enabled"
    }

    dynamic "source_selection_criteria" {
      for_each = var.kms_key_arn == null ? [] : [1]

      content {
        sse_kms_encrypted_objects {
          status = "Enabled"
        }
      }
    }

    destination {
      bucket        = aws_s3_bucket.processed_dr[0].arn
      storage_class = "STANDARD_IA"

      dynamic "encryption_configuration" {
        for_each = var.dr_kms_key_arn == null ? [] : [1]

        content {
          replica_kms_key_id = var.dr_kms_key_arn
        }
      }
    }
  }

  depends_on = [
    aws_s3_bucket_versioning.this,
    aws_s3_bucket_versioning.processed_dr,
    aws_iam_role_policy.replication,
  ]
}

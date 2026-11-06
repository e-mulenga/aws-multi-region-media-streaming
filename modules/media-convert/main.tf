# Module: media-convert - on-demand queue and the service role MediaConvert assumes.
# MediaConvert is available in af-south-1 (announced 2022-12-19, see docs/regional-availability.md).

resource "aws_iam_role" "mediaconvert" {
  name = "${var.name_prefix}-mediaconvert"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "mediaconvert.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "mediaconvert" {
  name = "mediaconvert-s3"
  role = aws_iam_role.mediaconvert.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Effect   = "Allow"
          Action   = ["s3:GetObject"]
          Resource = ["${var.ingestion_bucket_arn}/*"]
        },
        {
          Effect   = "Allow"
          Action   = ["s3:PutObject"]
          Resource = ["${var.processed_bucket_arn}/*"]
        },
        {
          Effect   = "Allow"
          Action   = ["s3:ListBucket"]
          Resource = [var.ingestion_bucket_arn, var.processed_bucket_arn]
        }
      ],
      var.s3_kms_key_arn == null ? [] : [{
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = [var.s3_kms_key_arn]
      }]
    )
  })
}

resource "aws_media_convert_queue" "main" {
  name         = "${var.name_prefix}-transcode"
  description  = "On-demand transcoding queue"
  pricing_plan = "ON_DEMAND"
  status       = "ACTIVE"
}

resource "aws_cloudwatch_metric_alarm" "jobs_errored" {
  alarm_name          = "${var.name_prefix}-mediaconvert-job-errors"
  alarm_description   = "MediaConvert jobs are failing in the transcode queue."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "JobsErroredCount"
  namespace           = "AWS/MediaConvert"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alarm_topic_arn]

  dimensions = {
    Queue = aws_media_convert_queue.main.arn
  }
}

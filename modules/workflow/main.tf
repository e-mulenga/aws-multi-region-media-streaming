# Module: workflow - S3 upload -> EventBridge -> Step Functions -> Lambda -> MediaConvert -> DynamoDB.

locals {
  fn_ingestion    = "${var.name_prefix}-media-ingestion"
  fn_notification = "${var.name_prefix}-media-notification"
  mc_arn          = "arn:${var.partition}:mediaconvert:${var.region}:${var.account_id}:*"
}

data "archive_file" "media_ingestion" {
  type        = "zip"
  output_path = "${path.module}/.build/media_ingestion.zip"
  source_file = "${path.module}/../../lambda/media-ingestion/handler.py"
}

data "archive_file" "media_notification" {
  type        = "zip"
  output_path = "${path.module}/.build/media_notification.zip"
  source_file = "${path.module}/../../lambda/media-notification/handler.py"
}

resource "aws_cloudwatch_log_group" "ingestion" {
  name              = "/aws/lambda/${local.fn_ingestion}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn
}

resource "aws_cloudwatch_log_group" "notification" {
  name              = "/aws/lambda/${local.fn_notification}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn
}

resource "aws_cloudwatch_log_group" "sfn" {
  name              = "/aws/vendedlogs/states/${var.name_prefix}-media-processing"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn
}

# ---- Lambda role ----
resource "aws_iam_role" "lambda" {
  name = "${var.name_prefix}-workflow-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda" {
  name = "workflow-lambda"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Effect   = "Allow"
          Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
          Resource = ["${aws_cloudwatch_log_group.ingestion.arn}:*", "${aws_cloudwatch_log_group.notification.arn}:*"]
        },
        {
          Effect   = "Allow"
          Action   = ["mediaconvert:CreateJob", "mediaconvert:GetJob"]
          Resource = [local.mc_arn]
        },
        {
          # DescribeEndpoints does not support resource-level permissions.
          Effect   = "Allow"
          Action   = ["mediaconvert:DescribeEndpoints"]
          Resource = ["*"]
        },
        {
          Effect   = "Allow"
          Action   = ["s3:GetObject"]
          Resource = ["${var.ingestion_bucket_arn}/*"]
        },
        {
          Effect   = "Allow"
          Action   = ["dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:GetItem"]
          Resource = [var.content_table_arn]
        },
        {
          Effect   = "Allow"
          Action   = ["sns:Publish"]
          Resource = [var.alarm_topic_arn]
        },
        {
          Effect   = "Allow"
          Action   = ["iam:PassRole"]
          Resource = [var.mediaconvert_role_arn]

          Condition = {
            StringEquals = { "iam:PassedToService" = "mediaconvert.amazonaws.com" }
          }
        }
      ],
      var.enable_xray ? [{
        Effect   = "Allow"
        Action   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
        Resource = "*"
      }] : [],
      var.dynamodb_kms_key_arn == null ? [] : [{
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = [var.dynamodb_kms_key_arn]
      }],
      var.s3_kms_key_arn == null ? [] : [{
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = [var.s3_kms_key_arn]
      }]
    )
  })
}

resource "aws_lambda_function" "ingestion" {
  function_name    = local.fn_ingestion
  role             = aws_iam_role.lambda.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  architectures    = ["arm64"]
  timeout          = 60
  memory_size      = 256
  kms_key_arn      = var.lambda_kms_key_arn
  filename         = data.archive_file.media_ingestion.output_path
  source_code_hash = data.archive_file.media_ingestion.output_base64sha256

  environment {
    variables = {
      MEDIACONVERT_QUEUE_ARN = var.mediaconvert_queue_arn
      MEDIACONVERT_ROLE_ARN  = var.mediaconvert_role_arn
      OUTPUT_BUCKET          = var.processed_bucket_id
      CONTENT_TABLE_NAME     = var.content_table_name
      ENVIRONMENT            = var.environment
    }
  }

  tracing_config {
    mode = var.enable_xray ? "Active" : "PassThrough"
  }

  depends_on = [aws_cloudwatch_log_group.ingestion, aws_iam_role_policy.lambda]
}

resource "aws_lambda_function" "notification" {
  function_name    = local.fn_notification
  role             = aws_iam_role.lambda.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  architectures    = ["arm64"]
  timeout          = 30
  memory_size      = 128
  kms_key_arn      = var.lambda_kms_key_arn
  filename         = data.archive_file.media_notification.output_path
  source_code_hash = data.archive_file.media_notification.output_base64sha256

  environment {
    variables = {
      ALERTS_TOPIC       = var.alarm_topic_arn
      CONTENT_TABLE_NAME = var.content_table_name
      ENVIRONMENT        = var.environment
    }
  }

  tracing_config {
    mode = var.enable_xray ? "Active" : "PassThrough"
  }

  depends_on = [aws_cloudwatch_log_group.notification, aws_iam_role_policy.lambda]
}

# ---- Step Functions ----
resource "aws_iam_role" "sfn" {
  name = "${var.name_prefix}-media-sfn"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "sfn" {
  name = "media-sfn"
  role = aws_iam_role.sfn.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Effect   = "Allow"
          Action   = ["lambda:InvokeFunction"]
          Resource = [aws_lambda_function.ingestion.arn, aws_lambda_function.notification.arn]
        },
        {
          # CloudWatch Logs delivery actions do not support resource-level permissions.
          Effect   = "Allow"
          Action   = ["logs:CreateLogDelivery", "logs:GetLogDelivery", "logs:UpdateLogDelivery", "logs:DeleteLogDelivery", "logs:ListLogDeliveries", "logs:PutResourcePolicy", "logs:DescribeResourcePolicies", "logs:DescribeLogGroups"]
          Resource = "*"
        }
      ],
      var.enable_xray ? [{
        Effect   = "Allow"
        Action   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords", "xray:GetSamplingRules", "xray:GetSamplingTargets"]
        Resource = "*"
      }] : []
    )
  })
}

locals {
  invoke = "arn:${var.partition}:states:::lambda:invoke"
}

resource "aws_sfn_state_machine" "media_processing" {
  name     = "${var.name_prefix}-media-processing"
  role_arn = aws_iam_role.sfn.arn
  type     = "STANDARD"

  logging_configuration {
    level                  = "ERROR"
    include_execution_data = false
    log_destination        = "${aws_cloudwatch_log_group.sfn.arn}:*"
  }

  tracing_configuration {
    enabled = var.enable_xray
  }

  definition = jsonencode({
    Comment        = "Media processing pipeline"
    StartAt        = "ValidateUpload"
    TimeoutSeconds = 14400 # bounds the transcode polling loop
    States = {
      ValidateUpload = {
        Type       = "Task"
        Resource   = local.invoke
        Parameters = { FunctionName = aws_lambda_function.ingestion.arn, Payload = { action = "validate", "input.$" = "$" } }
        ResultPath = "$.validation"
        Next       = "ChoiceOnValidation"
        Retry      = [{ ErrorEquals = ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException"], IntervalSeconds = 2, MaxAttempts = 3, BackoffRate = 2 }]
        Catch      = [{ ErrorEquals = ["States.ALL"], Next = "HandleError", ResultPath = "$.error" }]
      }
      ChoiceOnValidation = {
        Type    = "Choice"
        Choices = [{ Variable = "$.validation.Payload.valid", BooleanEquals = true, Next = "StartTranscoding" }]
        Default = "HandleError"
      }
      StartTranscoding = {
        Type       = "Task"
        Resource   = local.invoke
        Parameters = { FunctionName = aws_lambda_function.ingestion.arn, Payload = { action = "transcode", "input.$" = "$" } }
        ResultPath = "$.transcoding"
        Next       = "WaitForTranscoding"
        Catch      = [{ ErrorEquals = ["States.ALL"], Next = "HandleError", ResultPath = "$.error" }]
      }
      WaitForTranscoding = {
        Type    = "Wait"
        Seconds = 30
        Next    = "CheckTranscodingStatus"
      }
      CheckTranscodingStatus = {
        Type       = "Task"
        Resource   = local.invoke
        Parameters = { FunctionName = aws_lambda_function.ingestion.arn, Payload = { action = "check_status", "input.$" = "$" } }
        ResultPath = "$.status"
        Next       = "ChoiceOnStatus"
        Retry      = [{ ErrorEquals = ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException"], IntervalSeconds = 2, MaxAttempts = 3, BackoffRate = 2 }]
        Catch      = [{ ErrorEquals = ["States.ALL"], Next = "HandleError", ResultPath = "$.error" }]
      }
      ChoiceOnStatus = {
        Type = "Choice"
        Choices = [
          { Variable = "$.status.Payload.job_status", StringEquals = "COMPLETE", Next = "UpdateMetadata" },
          { Variable = "$.status.Payload.job_status", StringEquals = "ERROR", Next = "HandleError" },
          { Variable = "$.status.Payload.job_status", StringEquals = "CANCELED", Next = "HandleError" }
        ]
        Default = "WaitForTranscoding"
      }
      UpdateMetadata = {
        Type       = "Task"
        Resource   = local.invoke
        Parameters = { FunctionName = aws_lambda_function.ingestion.arn, Payload = { action = "update_metadata", "input.$" = "$" } }
        ResultPath = "$.metadata"
        Next       = "NotifyComplete"
        Catch      = [{ ErrorEquals = ["States.ALL"], Next = "HandleError", ResultPath = "$.error" }]
      }
      NotifyComplete = {
        Type       = "Task"
        Resource   = local.invoke
        Parameters = { FunctionName = aws_lambda_function.notification.arn, Payload = { action = "notify_success", "input.$" = "$" } }
        End        = true
      }
      HandleError = {
        Type       = "Task"
        Resource   = local.invoke
        Parameters = { FunctionName = aws_lambda_function.notification.arn, Payload = { action = "notify_error", "input.$" = "$" } }
        Next       = "WorkflowFailed"
      }
      WorkflowFailed = {
        Type  = "Fail"
        Error = "MediaProcessingFailed"
        Cause = "Media processing pipeline encountered an error"
      }
    }
  })
}

# ---- Trigger: new video object in the ingestion bucket ----
resource "aws_cloudwatch_event_rule" "upload" {
  name        = "${var.name_prefix}-media-upload"
  description = "Start the media workflow when a video lands in the ingestion bucket."

  event_pattern = jsonencode({
    source        = ["aws.s3"]
    "detail-type" = ["Object Created"]
    detail = {
      bucket = { name = [var.ingestion_bucket_id] }
      object = { key = [{ suffix = ".mp4" }, { suffix = ".mov" }, { suffix = ".avi" }, { suffix = ".mkv" }, { suffix = ".mxf" }] }
    }
  })
}

resource "aws_iam_role" "events" {
  name = "${var.name_prefix}-eb-start-sfn"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "events" {
  name = "start-execution"
  role = aws_iam_role.events.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["states:StartExecution"]
      Resource = [aws_sfn_state_machine.media_processing.arn]
    }]
  })
}

resource "aws_cloudwatch_event_target" "upload" {
  rule      = aws_cloudwatch_event_rule.upload.name
  target_id = "MediaProcessingWorkflow"
  arn       = aws_sfn_state_machine.media_processing.arn
  role_arn  = aws_iam_role.events.arn
}

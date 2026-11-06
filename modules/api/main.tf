# Module: api - HTTP API + two Lambda functions (content, analytics).
# Routes live under /api so CloudFront can route /api/* to this origin. Lambda is not VPC-attached
# (the Landing Zone has no NAT or interface endpoints; it only needs DynamoDB, which is public-endpoint).

locals {
  secure_auth = var.jwt_issuer != ""
  table_arns  = [var.content_table_arn, "${var.content_table_arn}/index/*", var.analytics_table_arn, "${var.analytics_table_arn}/index/*"]
}

data "archive_file" "content_api" {
  type        = "zip"
  output_path = "${path.module}/.build/content_api.zip"
  source_file = "${path.module}/../../lambda/content-api/handler.py"
}

data "archive_file" "analytics" {
  type        = "zip"
  output_path = "${path.module}/.build/analytics.zip"
  source_file = "${path.module}/../../lambda/analytics/handler.py"
}

resource "aws_iam_role" "lambda" {
  name = "${var.name_prefix}-api-lambda"

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
  name = "api-lambda"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Effect   = "Allow"
          Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
          Resource = ["${aws_cloudwatch_log_group.content_api.arn}:*", "${aws_cloudwatch_log_group.analytics.arn}:*"]
        },
        {
          Effect   = "Allow"
          Action   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:Query", "dynamodb:Scan"]
          Resource = local.table_arns
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
      }]
    )
  })
}

resource "aws_cloudwatch_log_group" "content_api" {
  name              = "/aws/lambda/${var.name_prefix}-content-api"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn
}

resource "aws_cloudwatch_log_group" "analytics" {
  name              = "/aws/lambda/${var.name_prefix}-analytics"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn
}

resource "aws_cloudwatch_log_group" "api_access" {
  name              = "/aws/apigateway/${var.name_prefix}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn
}

resource "aws_lambda_function" "content_api" {
  function_name    = "${var.name_prefix}-content-api"
  role             = aws_iam_role.lambda.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  architectures    = ["arm64"]
  timeout          = 29
  memory_size      = 512
  kms_key_arn      = var.lambda_kms_key_arn
  filename         = data.archive_file.content_api.output_path
  source_code_hash = data.archive_file.content_api.output_base64sha256

  environment {
    variables = {
      CONTENT_TABLE_NAME = var.content_table_name
      PUBLIC_BASE_HOST   = var.public_base_host
      ENVIRONMENT        = var.environment
    }
  }

  tracing_config {
    mode = var.enable_xray ? "Active" : "PassThrough"
  }

  depends_on = [aws_cloudwatch_log_group.content_api, aws_iam_role_policy.lambda]
}

resource "aws_lambda_function" "analytics" {
  function_name    = "${var.name_prefix}-analytics"
  role             = aws_iam_role.lambda.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  architectures    = ["arm64"]
  timeout          = 29
  memory_size      = 256
  kms_key_arn      = var.lambda_kms_key_arn
  filename         = data.archive_file.analytics.output_path
  source_code_hash = data.archive_file.analytics.output_base64sha256

  environment {
    variables = {
      ANALYTICS_TABLE_NAME = var.analytics_table_name
      ENVIRONMENT          = var.environment
    }
  }

  tracing_config {
    mode = var.enable_xray ? "Active" : "PassThrough"
  }

  depends_on = [aws_cloudwatch_log_group.analytics, aws_iam_role_policy.lambda]
}

resource "aws_apigatewayv2_api" "main" {
  name          = "${var.name_prefix}-api"
  protocol_type = "HTTP"
  description   = "Content and analytics API (fronted by CloudFront)"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_access.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      responseLength = "$context.responseLength"
      integrationErr = "$context.integrationErrorMessage"
    })
  }

  default_route_settings {
    throttling_burst_limit   = 1000
    throttling_rate_limit    = 500
    detailed_metrics_enabled = true
  }
}

resource "aws_apigatewayv2_authorizer" "jwt" {
  count = local.secure_auth ? 1 : 0

  api_id           = aws_apigatewayv2_api.main.id
  authorizer_type  = "JWT"
  name             = "jwt"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    issuer   = var.jwt_issuer
    audience = var.jwt_audience
  }
}

resource "aws_apigatewayv2_integration" "content_api" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.content_api.invoke_arn
  payload_format_version = "2.0"
  timeout_milliseconds   = 29000
}

resource "aws_apigatewayv2_integration" "analytics" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.analytics.invoke_arn
  payload_format_version = "2.0"
  timeout_milliseconds   = 29000
}

locals {
  # route key => { integration, protected }. Write routes require the JWT authorizer when configured.
  routes = {
    "GET /api/health"                 = { integration = aws_apigatewayv2_integration.content_api.id, protected = false }
    "GET /api/content"                = { integration = aws_apigatewayv2_integration.content_api.id, protected = false }
    "GET /api/content/{id}"           = { integration = aws_apigatewayv2_integration.content_api.id, protected = false }
    "GET /api/search"                 = { integration = aws_apigatewayv2_integration.content_api.id, protected = false }
    "POST /api/content"               = { integration = aws_apigatewayv2_integration.content_api.id, protected = true }
    "POST /api/analytics/events"      = { integration = aws_apigatewayv2_integration.analytics.id, protected = false }
    "GET /api/analytics/{content_id}" = { integration = aws_apigatewayv2_integration.analytics.id, protected = true }
  }
}

resource "aws_apigatewayv2_route" "this" {
  for_each = local.routes

  api_id             = aws_apigatewayv2_api.main.id
  route_key          = each.key
  target             = "integrations/${each.value.integration}"
  authorization_type = each.value.protected && local.secure_auth ? "JWT" : "NONE"
  authorizer_id      = each.value.protected && local.secure_auth ? aws_apigatewayv2_authorizer.jwt[0].id : null
}

resource "aws_lambda_permission" "content_api" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.content_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

resource "aws_lambda_permission" "analytics" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.analytics.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name          = "${var.name_prefix}-api-5xx"
  alarm_description   = "API 5xx errors are elevated."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "5xx"
  namespace           = "AWS/ApiGateway"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alarm_topic_arn]

  dimensions = {
    ApiId = aws_apigatewayv2_api.main.id
  }
}

resource "aws_cloudwatch_metric_alarm" "api_latency" {
  alarm_name          = "${var.name_prefix}-api-latency"
  alarm_description   = "API p99 integration latency above 2 s."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "IntegrationLatency"
  namespace           = "AWS/ApiGateway"
  period              = 60
  extended_statistic  = "p99"
  threshold           = 2000
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alarm_topic_arn]

  dimensions = {
    ApiId = aws_apigatewayv2_api.main.id
  }
}

# Module: monitoring - workflow alarm + one dashboard. CloudFront widgets read us-east-1 metrics.
# Other alarms live next to their resources (api, media-convert, edge, disaster-recovery).

resource "aws_cloudwatch_metric_alarm" "sfn_failed" {
  alarm_name          = "${var.name_prefix}-workflow-failures"
  alarm_description   = "Media processing executions are failing."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ExecutionsFailed"
  namespace           = "AWS/States"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.alarm_topic_arn]

  dimensions = {
    StateMachineArn = var.workflow_state_machine_arn
  }
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.name_prefix}-media-platform"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "text", x = 0, y = 0, width = 24, height = 2
        properties = {
          markdown = "# Media platform - ${upper(var.environment)}\nPrimary af-south-1, DR eu-west-1. CloudFront widgets read us-east-1 metrics (global service)."
        }
      },
      {
        type = "metric", x = 0, y = 2, width = 8, height = 6
        properties = {
          region  = "us-east-1"
          title   = "CDN requests"
          period  = 300
          stat    = "Sum"
          view    = "timeSeries"
          metrics = [["AWS/CloudFront", "Requests", "DistributionId", var.cloudfront_distribution_id, "Region", "Global"]]
        }
      },
      {
        type = "metric", x = 8, y = 2, width = 8, height = 6
        properties = {
          region  = "us-east-1"
          title   = "CDN 5xx error rate (%)"
          period  = 300
          stat    = "Average"
          view    = "timeSeries"
          metrics = [["AWS/CloudFront", "5xxErrorRate", "DistributionId", var.cloudfront_distribution_id, "Region", "Global"]]
        }
      },
      {
        type = "metric", x = 16, y = 2, width = 8, height = 6
        properties = {
          region  = var.region
          title   = "API requests and 5xx"
          period  = 60
          stat    = "Sum"
          view    = "timeSeries"
          metrics = [["AWS/ApiGateway", "Count", "ApiId", var.api_id], ["AWS/ApiGateway", "5xx", "ApiId", var.api_id]]
        }
      },
      {
        type = "metric", x = 0, y = 8, width = 12, height = 6
        properties = {
          region  = var.region
          title   = "MediaConvert jobs"
          period  = 300
          stat    = "Sum"
          view    = "timeSeries"
          metrics = [["AWS/MediaConvert", "JobsCompletedCount", "Queue", var.mediaconvert_queue_arn], ["AWS/MediaConvert", "JobsErroredCount", "Queue", var.mediaconvert_queue_arn]]
        }
      },
      {
        type = "metric", x = 12, y = 8, width = 12, height = 6
        properties = {
          region  = var.region
          title   = "Workflow executions"
          period  = 300
          stat    = "Sum"
          view    = "timeSeries"
          metrics = [["AWS/States", "ExecutionsSucceeded", "StateMachineArn", var.workflow_state_machine_arn], ["AWS/States", "ExecutionsFailed", "StateMachineArn", var.workflow_state_machine_arn]]
        }
      }
    ]
  })
}

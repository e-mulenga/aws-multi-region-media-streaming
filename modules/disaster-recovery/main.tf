# Module: disaster-recovery - health check, alarm and AWS Backup with copy to eu-west-1.
# Failover itself is a documented, human-approved runbook step (see docs/dr-and-resilience.md).
# AWS Backup in af-south-1 and the cross-region copy to eu-west-1 were not individually verified
# against AWS documentation (docs/regional-availability.md).

resource "aws_route53_health_check" "api" {
  fqdn              = var.api_domain
  port              = 443
  type              = "HTTPS"
  resource_path     = "/api/health"
  failure_threshold = 3
  request_interval  = 30

  tags = { Name = "${var.name_prefix}-api-health" }
}

# Route 53 health-check metrics exist only in us-east-1, so this alarm lives there.
resource "aws_cloudwatch_metric_alarm" "primary_unhealthy" {
  provider = aws.global_edge

  alarm_name          = "${var.name_prefix}-primary-unhealthy"
  alarm_description   = "Primary region API health check failing. Decide on DR failover per the runbook."
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "HealthCheckStatus"
  namespace           = "AWS/Route53"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1
  treat_missing_data  = "breaching"
  alarm_actions       = [var.edge_alerts_topic_arn]

  dimensions = {
    HealthCheckId = aws_route53_health_check.api.id
  }
}

resource "aws_backup_vault" "primary" {
  name        = "${var.name_prefix}-vault"
  kms_key_arn = var.backup_kms_key_arn
}

resource "aws_backup_vault" "dr" {
  provider = aws.ireland

  name        = "${var.name_prefix}-vault-dr"
  kms_key_arn = var.dr_backup_kms_key_arn
}

resource "aws_iam_role" "backup" {
  name = "${var.name_prefix}-backup"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "backup" {
  for_each = toset([
    "AWSBackupServiceRolePolicyForBackup",
    "AWSBackupServiceRolePolicyForRestores",
  ])

  role       = aws_iam_role.backup.name
  policy_arn = "arn:${var.partition}:iam::aws:policy/service-role/${each.value}"
}

resource "aws_backup_plan" "main" {
  name = "${var.name_prefix}-plan"

  rule {
    rule_name         = "daily"
    target_vault_name = aws_backup_vault.primary.name
    schedule          = "cron(0 1 * * ? *)"

    lifecycle {
      delete_after = var.environment == "prod" ? 365 : 35
    }

    copy_action {
      destination_vault_arn = aws_backup_vault.dr.arn

      lifecycle {
        delete_after = var.environment == "prod" ? 365 : 35
      }
    }
  }
}

resource "aws_backup_selection" "main" {
  name         = "${var.name_prefix}-selection"
  plan_id      = aws_backup_plan.main.id
  iam_role_arn = aws_iam_role.backup.arn
  resources    = var.backup_resource_arns
}

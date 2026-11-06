output "content_table_name" {
  description = "Content metadata table name."
  value       = aws_dynamodb_table.content_metadata.name
}

output "content_table_arn" {
  description = "Content metadata table ARN."
  value       = aws_dynamodb_table.content_metadata.arn
}

output "analytics_table_name" {
  description = "Viewer analytics table name."
  value       = aws_dynamodb_table.viewer_analytics.name
}

output "analytics_table_arn" {
  description = "Viewer analytics table ARN."
  value       = aws_dynamodb_table.viewer_analytics.arn
}

output "aurora_primary_cluster_arn" {
  description = "Aurora primary cluster ARN (null when Aurora is off)."
  value       = var.enable_aurora ? aws_rds_cluster.primary[0].arn : null
}

output "aurora_master_secret_arn" {
  description = "RDS-managed master-user secret ARN."
  value       = var.enable_aurora ? aws_rds_cluster.primary[0].master_user_secret[0].secret_arn : null
}

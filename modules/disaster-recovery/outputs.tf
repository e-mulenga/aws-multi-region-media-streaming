output "health_check_id" {
  description = "Route 53 health check ID."
  value       = aws_route53_health_check.api.id
}

output "dr_vault_arn" {
  description = "eu-west-1 backup vault ARN."
  value       = aws_backup_vault.dr.arn
}

output "distribution_id" {
  description = "CloudFront distribution ID."
  value       = aws_cloudfront_distribution.main.id
}

output "distribution_arn" {
  description = "CloudFront distribution ARN."
  value       = aws_cloudfront_distribution.main.arn
}

output "distribution_domain_name" {
  description = "CloudFront domain name."
  value       = aws_cloudfront_distribution.main.domain_name
}

output "waf_acl_arn" {
  description = "CloudFront WAF web ACL ARN."
  value       = aws_wafv2_web_acl.cdn.arn
}

output "edge_alerts_topic_arn" {
  description = "us-east-1 topic used by CloudFront and Route 53 alarms."
  value       = aws_sns_topic.edge_alerts.arn
}

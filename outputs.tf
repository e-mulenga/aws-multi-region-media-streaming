output "cloudfront_domain_name" {
  description = "CloudFront domain name."
  value       = module.edge.distribution_domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID."
  value       = module.edge.distribution_id
}

output "api_domain" {
  description = "Direct execute-api hostname (prefer the CloudFront /api path)."
  value       = module.api.api_domain
}

output "ingestion_bucket" {
  description = "Upload videos here."
  value       = module.storage.ingestion_bucket_id
}

output "processed_bucket" {
  description = "Transcoded media (af-south-1)."
  value       = module.storage.processed_bucket_id
}

output "processed_dr_bucket" {
  description = "Replica (eu-west-1)."
  value       = module.storage.processed_dr_bucket_id
}

output "workflow_state_machine_arn" {
  description = "Media workflow state machine."
  value       = module.workflow.state_machine_arn
}

output "mediaconvert_queue_arn" {
  description = "Transcode queue."
  value       = module.media_convert.queue_arn
}

output "media_package_hls_ingest_endpoints" {
  description = "Live ingest endpoints (null when MediaPackage is off)."
  value       = var.enable_media_package ? module.media_package[0].hls_ingest_endpoints : null
}

output "media_package_playback_path" {
  description = "Live playback path on the CloudFront domain."
  value       = var.enable_media_package ? module.media_package[0].playback_path : null
}

output "dashboard_name" {
  description = "CloudWatch dashboard."
  value       = module.monitoring.dashboard_name
}

output "health_check_id" {
  description = "Route 53 health check."
  value       = module.disaster_recovery.health_check_id
}

output "landing_zone_consumed" {
  description = "Landing Zone values this stack consumed (no secrets)."
  value = {
    key_strategy        = local.key_strategy
    route53_zone_id     = local.route53_zone_id
    cloudfront_cert_arn = local.cloudfront_cert_arn
    alarm_topic_arn     = local.alarm_topic_arn
    primary_vpc_id      = local.primary_vpc_id
    dr_vpc_id           = local.dr_vpc_id
  }
}

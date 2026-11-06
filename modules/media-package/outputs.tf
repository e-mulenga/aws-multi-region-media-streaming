locals {
  endpoint_url = aws_cloudformation_stack.endpoint.outputs["EndpointUrl"]
  url_parts    = split("/", replace(local.endpoint_url, "https://", ""))
}

output "channel_arn" {
  description = "MediaPackage channel ARN."
  value       = aws_media_package_channel.live.arn
}

output "hls_ingest_endpoints" {
  description = "HLS ingest endpoints (URLs; credentials are managed in MediaPackage)."
  value       = [for e in aws_media_package_channel.live.hls_ingest[0].ingest_endpoints : e.url]
}

output "origin_domain" {
  description = "Hostname of the HLS origin endpoint (CloudFront origin)."
  value       = local.url_parts[0]
}

output "playback_path" {
  description = "Path of the HLS manifest on the origin."
  value       = "/${join("/", slice(local.url_parts, 1, length(local.url_parts)))}"
}

output "cdn_identifier" {
  description = "Value CloudFront must send in X-MediaPackage-CDNIdentifier."
  value       = random_password.cdn_identifier.result
  sensitive   = true
}

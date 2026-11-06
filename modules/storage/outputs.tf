output "ingestion_bucket_id" {
  description = "Ingestion bucket name."
  value       = aws_s3_bucket.this["ingestion"].id
}

output "ingestion_bucket_arn" {
  description = "Ingestion bucket ARN."
  value       = aws_s3_bucket.this["ingestion"].arn
}

output "processed_bucket_id" {
  description = "Processed bucket name."
  value       = aws_s3_bucket.this["processed"].id
}

output "processed_bucket_arn" {
  description = "Processed bucket ARN."
  value       = aws_s3_bucket.this["processed"].arn
}

output "processed_bucket_regional_domain_name" {
  description = "Regional S3 domain of the processed bucket (CloudFront origin)."
  value       = aws_s3_bucket.this["processed"].bucket_regional_domain_name
}

output "archive_bucket_id" {
  description = "Archive bucket name."
  value       = aws_s3_bucket.this["archive"].id
}

output "archive_bucket_arn" {
  description = "Archive bucket ARN."
  value       = aws_s3_bucket.this["archive"].arn
}

output "processed_dr_bucket_id" {
  description = "eu-west-1 replica bucket name (null when replication is off)."
  value       = var.enable_replication ? aws_s3_bucket.processed_dr[0].id : null
}

output "processed_dr_bucket_arn" {
  description = "eu-west-1 replica bucket ARN."
  value       = var.enable_replication ? aws_s3_bucket.processed_dr[0].arn : null
}

output "processed_dr_bucket_regional_domain_name" {
  description = "Regional S3 domain of the replica bucket (CloudFront failover origin)."
  value       = var.enable_replication ? aws_s3_bucket.processed_dr[0].bucket_regional_domain_name : null
}

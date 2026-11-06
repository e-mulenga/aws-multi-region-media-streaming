output "queue_arn" {
  description = "Transcode queue ARN."
  value       = aws_media_convert_queue.main.arn
}

output "role_arn" {
  description = "MediaConvert service role ARN."
  value       = aws_iam_role.mediaconvert.arn
}

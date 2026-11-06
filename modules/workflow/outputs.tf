output "state_machine_arn" {
  description = "Media processing state machine ARN."
  value       = aws_sfn_state_machine.media_processing.arn
}

output "ingestion_function_name" {
  description = "Ingestion Lambda name."
  value       = aws_lambda_function.ingestion.function_name
}

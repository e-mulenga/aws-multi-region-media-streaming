output "api_id" {
  description = "HTTP API ID."
  value       = aws_apigatewayv2_api.main.id
}

output "api_domain" {
  description = "execute-api hostname (CloudFront origin and health-check target)."
  value       = replace(aws_apigatewayv2_api.main.api_endpoint, "https://", "")
}

output "content_function_name" {
  description = "Content Lambda name."
  value       = aws_lambda_function.content_api.function_name
}

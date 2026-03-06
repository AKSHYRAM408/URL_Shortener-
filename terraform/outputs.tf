# ──────────────────────────────────────────────────────────────────
# Outputs — printed after `terraform apply`
# ──────────────────────────────────────────────────────────────────

output "api_base_url" {
  description = "Base URL of the deployed API Gateway stage"
  value       = aws_api_gateway_stage.prod.invoke_url
}

output "shorten_endpoint" {
  description = "Full URL to shorten a URL (POST)"
  value       = "${aws_api_gateway_stage.prod.invoke_url}/shorten"
}

output "redirect_endpoint" {
  description = "Base URL for redirects (GET /<code>)"
  value       = "${aws_api_gateway_stage.prod.invoke_url}/{code}"
}

output "stats_endpoint" {
  description = "Base URL for stats (GET /stats/<code>)"
  value       = "${aws_api_gateway_stage.prod.invoke_url}/stats/{code}"
}

output "lambda_function_name" {
  description = "Name of the deployed Lambda function"
  value       = aws_lambda_function.url_shortener.function_name
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  value       = aws_dynamodb_table.urls.name
}

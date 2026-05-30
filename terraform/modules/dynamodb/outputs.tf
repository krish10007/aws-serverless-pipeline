output "table_name" {
  description = "DynamoDB table name — passed to Lambda #2 as env var"
  value       = aws_dynamodb_table.pipeline_records.name
}

output "table_arn" {
  description = "DynamoDB table ARN — needed for Lambda #2 IAM permissions"
  value       = aws_dynamodb_table.pipeline_records.arn
}
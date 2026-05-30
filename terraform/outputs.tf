
output "data_bucket_name" {
  description = "Upload CSV/JSON files here to trigger the pipeline"
  value       = module.s3.bucket_name
}

output "dynamodb_table_name" {
  description = "DynamoDB table where processed records land"
  value       = module.dynamodb.table_name
}

output "dashboard_url" {
  description = "CloudWatch dashboard URL"
  value       = module.monitoring.dashboard_url
}
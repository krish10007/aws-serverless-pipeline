output "bucket_name" {
  description = "Name of the data bucket"
  value       = aws_s3_bucket.data_bucket.id
}

output "bucket_arn" {
  description = "ARN of the data bucket — needed for Lambda IAM permissions"
  value       = aws_s3_bucket.data_bucket.arn
}
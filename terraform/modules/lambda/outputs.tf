output "processor_lambda_arn" {
  description = "ARN of the processor Lambda — S3 and IAM need this"
  value       = aws_lambda_function.processor.arn
}

output "processor_lambda_name" {
  description = "Name of the processor Lambda — for CloudWatch alarms"
  value       = aws_lambda_function.processor.function_name
}

output "processor_lambda_role_arn" {
  description = "IAM role ARN — exported for reference"
  value       = aws_iam_role.processor_lambda_role.arn
}
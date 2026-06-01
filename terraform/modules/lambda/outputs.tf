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

output "writer_lambda_name" {
  description = "Writer Lambda name — for CloudWatch alarms"
  value       = aws_lambda_function.writer.function_name
}

output "processor_log_group_name" {
  value = aws_cloudwatch_log_group.processor.name
}

output "writer_log_group_name" {
  value = aws_cloudwatch_log_group.writer.name
}
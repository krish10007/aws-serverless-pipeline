output "queue_url" {
  description = "URL Lambda #1 uses to send messages"
  value       = aws_sqs_queue.main.url
}

output "queue_arn" {
  description = "ARN for IAM permissions and Lambda #2 trigger"
  value       = aws_sqs_queue.main.arn
}

output "dlq_arn" {
  description = "DLQ ARN for monitoring and SNS alerting"
  value       = aws_sqs_queue.dlq.arn
}

output "dlq_name" {
  description = "DLQ name for CloudWatch alarm dimensions"
  value       = aws_sqs_queue.dlq.name
}

output "dlq_alarm_name" {
  description = "CloudWatch alarm name — referenced by monitoring module"
  value       = aws_cloudwatch_metric_alarm.dlq_depth.alarm_name
}
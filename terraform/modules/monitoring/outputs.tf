output "sns_topic_arn" {
  description = "SNS topic ARN — for adding more subscribers later"
  value       = aws_sns_topic.pipeline_alerts.arn
}
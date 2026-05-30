output "sns_topic_arn" {
  description = "SNS topic ARN — for adding more subscribers later"
  value       = aws_sns_topic.pipeline_alerts.arn
}

output "dashboard_url" {
  description = "Direct link to the CloudWatch dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home#dashboards:name=${aws_cloudwatch_dashboard.pipeline.dashboard_name}"
}
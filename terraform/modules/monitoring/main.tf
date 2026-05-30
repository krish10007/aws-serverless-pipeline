# -------------------------------------------------------
# SNS TOPIC — the central alert hub
# -------------------------------------------------------
resource "aws_sns_topic" "pipeline_alerts" {
  name = "${var.project_name}-alerts-${var.environment}"

  tags = {
    Name = "${var.project_name}-alerts"
  }
}

# Email subscription — SNS will send you a confirmation email
# You MUST click the confirmation link before alerts will deliver
resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.pipeline_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# -------------------------------------------------------
# WIRE SNS TO THE EXISTING DLQ ALARM
# The alarm was created in the SQS module
# We update it here to add the SNS action
# -------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "dlq_depth_with_sns" {
  alarm_name          = var.dlq_alarm_name
  alarm_description   = "Messages landing in DLQ — pipeline failures detected"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = "${var.project_name}-dlq-${var.environment}.fifo"
  }

  # Now wired to SNS — this is the line that was missing before
  alarm_actions = [aws_sns_topic.pipeline_alerts.arn]
  ok_actions    = [aws_sns_topic.pipeline_alerts.arn]  # alerts when alarm clears too
}

# -------------------------------------------------------
# LAMBDA ERROR RATE ALARMS
# Alerts if either Lambda throws errors
# Uses the default Lambda/Errors metric — no custom code needed
# -------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "processor_errors" {
  alarm_name          = "${var.project_name}-processor-errors-${var.environment}"
  alarm_description   = "Processor Lambda is throwing errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2        # must breach for 2 consecutive periods
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = var.processor_lambda_name
  }

  alarm_actions = [aws_sns_topic.pipeline_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "writer_errors" {
  alarm_name          = "${var.project_name}-writer-errors-${var.environment}"
  alarm_description   = "Writer Lambda is throwing errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = var.writer_lambda_name
  }

  alarm_actions = [aws_sns_topic.pipeline_alerts.arn]
}
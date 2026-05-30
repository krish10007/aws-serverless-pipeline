# -------------------------------------------------------
# SNS TOPIC — the central alert hub
# -------------------------------------------------------
resource "aws_sns_topic" "pipeline_alerts" {
  name = "${var.project_name}-alerts-${var.environment}"

  tags = {
    Name = "${var.project_name}-alerts"
  }
}

resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.pipeline_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

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

  alarm_actions = [aws_sns_topic.pipeline_alerts.arn]
  ok_actions    = [aws_sns_topic.pipeline_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "processor_errors" {
  alarm_name          = "${var.project_name}-processor-errors-${var.environment}"
  alarm_description   = "Processor Lambda is throwing errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
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

resource "aws_cloudwatch_metric_alarm" "processor_latency" {
  alarm_name          = "${var.project_name}-processor-latency-${var.environment}"
  alarm_description   = "File processing latency is too high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "FileProcessingLatency"
  namespace           = "${var.project_name}/Processor"
  period              = 60
  extended_statistic  = "p99"
  threshold           = 10000
  treat_missing_data  = "notBreaching"

  dimensions = {
    Environment = var.environment
  }

  alarm_actions = [aws_sns_topic.pipeline_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "validation_errors" {
  alarm_name          = "${var.project_name}-validation-errors-${var.environment}"
  alarm_description   = "Records are failing validation in the processor"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ValidationErrors"
  namespace           = "${var.project_name}/Processor"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  treat_missing_data  = "notBreaching"

  dimensions = {
    Environment = var.environment
  }

  alarm_actions = [aws_sns_topic.pipeline_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "write_failures" {
  alarm_name          = "${var.project_name}-write-failures-${var.environment}"
  alarm_description   = "Writer Lambda is failing to write records to DynamoDB"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "WriteFailures"
  namespace           = "${var.project_name}/Writer"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    Environment = var.environment
  }

  alarm_actions = [aws_sns_topic.pipeline_alerts.arn]
}

resource "aws_cloudwatch_log_metric_filter" "processor_errors" {
  name           = "${var.project_name}-processor-error-logs"
  log_group_name = "/aws/lambda/${var.project_name}-processor-${var.environment}"
  pattern        = "{ $.level = \"ERROR\" }"

  metric_transformation {
    name      = "ErrorLogCount"
    namespace = "${var.project_name}/Processor"
    value     = "1"
    unit      = "Count"
  }
}

resource "aws_cloudwatch_log_metric_filter" "writer_errors" {
  name           = "${var.project_name}-writer-error-logs"
  log_group_name = "/aws/lambda/${var.project_name}-writer-${var.environment}"
  pattern        = "{ $.level = \"ERROR\" }"

  metric_transformation {
    name      = "ErrorLogCount"
    namespace = "${var.project_name}/Writer"
    value     = "1"
    unit      = "Count"
  }
}

resource "aws_cloudwatch_dashboard" "pipeline" {
  dashboard_name = "${var.project_name}-${var.environment}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 2
        properties = {
          markdown = "# Serverless Pipeline Dashboard\nRegion: ${var.aws_region} | Environment: ${var.environment}"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 2
        width  = 8
        height = 6
        properties = {
          region  = var.aws_region
          title   = "Records Processed (Processor)"
          view    = "timeSeries"
          period  = 60
          stat    = "Sum"
          metrics = [["${var.project_name}/Processor", "RecordsProcessed", "Environment", var.environment]]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 2
        width  = 8
        height = 6
        properties = {
          region  = var.aws_region
          title   = "Records Written (Writer)"
          view    = "timeSeries"
          period  = 60
          stat    = "Sum"
          metrics = [["${var.project_name}/Writer", "RecordsWritten", "Environment", var.environment]]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 2
        width  = 8
        height = 6
        properties = {
          region  = var.aws_region
          title   = "SQS Batch Sizes"
          view    = "timeSeries"
          period  = 60
          stat    = "Average"
          metrics = [["${var.project_name}/Writer", "BatchSize", "Environment", var.environment]]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 8
        width  = 8
        height = 6
        properties = {
          region  = var.aws_region
          title   = "File Processing Latency p99 (ms)"
          view    = "timeSeries"
          period  = 60
          stat    = "p99"
          metrics = [["${var.project_name}/Processor", "FileProcessingLatency", "Environment", var.environment]]
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 8
        width  = 8
        height = 6
        properties = {
          region  = var.aws_region
          title   = "DynamoDB Write Latency p99 (ms)"
          view    = "timeSeries"
          period  = 60
          stat    = "p99"
          metrics = [["${var.project_name}/Writer", "WriteLatency", "Environment", var.environment]]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 8
        width  = 8
        height = 6
        properties = {
          region  = var.aws_region
          title   = "Invocation Latency p99 (ms)"
          view    = "timeSeries"
          period  = 60
          stat    = "p99"
          metrics = [
            ["${var.project_name}/Processor", "TotalLatency", "Environment", var.environment, { "label" : "Processor" }],
            ["${var.project_name}/Writer", "InvocationLatency", "Environment", var.environment, { "label" : "Writer" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 14
        width  = 8
        height = 6
        properties = {
          region  = var.aws_region
          title   = "DLQ Depth (failures)"
          view    = "timeSeries"
          period  = 60
          stat    = "Sum"
          metrics = [["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", "${var.project_name}-dlq-${var.environment}.fifo"]]
          annotations = {
            horizontal = [{ value = 1, label = "Alert threshold", color = "#ff0000" }]
          }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 14
        width  = 8
        height = 6
        properties = {
          region  = var.aws_region
          title   = "Lambda Error Rates"
          view    = "timeSeries"
          period  = 60
          stat    = "Sum"
          metrics = [
            ["AWS/Lambda", "Errors", "FunctionName", var.processor_lambda_name, { "label" : "Processor Errors" }],
            ["AWS/Lambda", "Errors", "FunctionName", var.writer_lambda_name, { "label" : "Writer Errors" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 14
        width  = 8
        height = 6
        properties = {
          region  = var.aws_region
          title   = "Validation Errors"
          view    = "timeSeries"
          period  = 300
          stat    = "Sum"
          metrics = [["${var.project_name}/Processor", "ValidationErrors", "Environment", var.environment]]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 20
        width  = 12
        height = 6
        properties = {
          region  = var.aws_region
          title   = "Lambda Duration (ms)"
          view    = "timeSeries"
          period  = 60
          stat    = "Average"
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", var.processor_lambda_name, { "label" : "Processor" }],
            ["AWS/Lambda", "Duration", "FunctionName", var.writer_lambda_name, { "label" : "Writer" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 20
        width  = 12
        height = 6
        properties = {
          region  = var.aws_region
          title   = "DynamoDB Consumed Write Units"
          view    = "timeSeries"
          period  = 60
          stat    = "Sum"
          metrics = [["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", var.dynamodb_table_name]]
        }
      }
    ]
  })
}
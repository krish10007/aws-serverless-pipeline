# -------------------------------------------------------
# DEAD LETTER QUEUE — must be created before main queue
# because main queue references its ARN
# -------------------------------------------------------
resource "aws_sqs_queue" "dlq" {
  name = "${var.project_name}-dlq-${var.environment}.fifo"

  # FIFO queues must have .fifo suffix — AWS requirement
  fifo_queue = true

  # How long failed messages stay in DLQ before expiring
  # 14 days gives you time to investigate and replay
  message_retention_seconds = 1209600  # 14 days

  tags = {
    Name = "${var.project_name}-dlq"
  }
}

# -------------------------------------------------------
# MAIN QUEUE — where Lambda #1 sends records
# Lambda #2 reads from here
# -------------------------------------------------------
resource "aws_sqs_queue" "main" {
  name       = "${var.project_name}-queue-${var.environment}.fifo"
  fifo_queue = true

  # Content-based deduplication uses hash of message body
  # Combined with our MessageDeduplicationId = no duplicate records
  content_based_deduplication = true

  # How long a message is hidden after Lambda #2 picks it up
  # If Lambda #2 doesn't delete it within this window, SQS retries
  # Set this higher than your Lambda #2 timeout
  visibility_timeout_seconds = 300  # matches Lambda timeout

  # How long messages stay in queue if never processed
  message_retention_seconds = 86400  # 1 day

  # Redrive policy — after 3 failed attempts, send to DLQ
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3  # try 3 times before giving up
  })

  tags = {
    Name = "${var.project_name}-main-queue"
  }
}

# -------------------------------------------------------
# CLOUDWATCH ALARM — fires when anything lands in the DLQ
# Wired to SNS in the monitoring module later
# We define the alarm here since it's tightly coupled to the queue
# -------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "dlq_depth" {
  alarm_name          = "${var.project_name}-dlq-depth-${var.environment}"
  alarm_description   = "Messages are landing in the DLQ — pipeline failures detected"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60   # check every 60 seconds
  statistic           = "Sum"
  threshold           = 0    # alarm if even 1 message is in DLQ
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.dlq.name
  }

  # SNS topic ARN will be added when monitoring module is built
  # alarm_actions = [var.sns_topic_arn]
}
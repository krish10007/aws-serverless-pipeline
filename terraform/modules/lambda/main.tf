# -------------------------------------------------------
# IAM ROLE — what the Lambda function is allowed to do
# Lambda needs a role to act as; this is like its identity card
# -------------------------------------------------------
resource "aws_iam_role" "processor_lambda_role" {
  name = "${var.project_name}-processor-role-${var.environment}"

  # Trust policy — allows Lambda service to assume this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Attach AWS managed policy for basic Lambda execution
# Gives Lambda permission to write its own logs to CloudWatch
resource "aws_iam_role_policy_attachment" "processor_basic_execution" {
  role       = aws_iam_role.processor_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy — specific permissions our Lambda actually needs
resource "aws_iam_role_policy" "processor_lambda_policy" {
  name = "${var.project_name}-processor-policy-${var.environment}"
  role = aws_iam_role.processor_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Read files from S3 data bucket
        Sid    = "ReadFromS3"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectAttributes"
        ]
        Resource = "${var.data_bucket_arn}/*"
      },
      {
        # Send messages to SQS queue
        Sid    = "WriteToSQS"
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:SendMessageBatch",
          "sqs:GetQueueAttributes"
        ]
        Resource = var.sqs_queue_arn
      },
      {
        # Push custom metrics to CloudWatch
        Sid    = "PushCloudWatchMetrics"
        Effect = "Allow"
        Action = ["cloudwatch:PutMetricData"]
        Resource = "*"  # CloudWatch metrics don't support resource-level restrictions
      }
    ]
  })
}

# -------------------------------------------------------
# PACKAGE THE LAMBDA CODE
# Terraform zips the src/processor/ folder automatically
# -------------------------------------------------------
data "archive_file" "processor_lambda" {
  type        = "zip"
  source_dir  = "${path.root}/../src/processor"
  output_path = "${path.root}/../src/processor/processor_lambda.zip"
}

# -------------------------------------------------------
# THE LAMBDA FUNCTION ITSELF
# -------------------------------------------------------
resource "aws_lambda_function" "processor" {
  function_name = "${var.project_name}-processor-${var.environment}"
  description   = "Reads files from S3, transforms records, sends to SQS"

  # The zipped code
  filename         = data.archive_file.processor_lambda.output_path
  source_code_hash = data.archive_file.processor_lambda.output_base64sha256

  runtime = "python3.11"
  handler = "handler.handler"  # filename.function_name

  role = aws_iam_role.processor_lambda_role.arn

  # Memory and timeout — tune these after load testing
  memory_size = 256   # MB
  timeout     = 300   # seconds (5 min max for large files)

  # Environment variables — your Python code reads these with os.environ
  environment {
    variables = {
      SQS_QUEUE_URL = var.sqs_queue_url
      ENVIRONMENT   = var.environment
      PROJECT_NAME  = var.project_name
    }
  }

  # Structured logging config
  logging_config {
    log_format = "JSON"  # tells Lambda runtime to treat logs as JSON
    log_group  = aws_cloudwatch_log_group.processor.name
  }

  depends_on = [
    aws_iam_role_policy_attachment.processor_basic_execution,
    aws_cloudwatch_log_group.processor,
  ]
}

# -------------------------------------------------------
# CLOUDWATCH LOG GROUP
# Explicitly managed so we control retention
# If you don't create this, AWS auto-creates it with no expiry
# -------------------------------------------------------
resource "aws_cloudwatch_log_group" "processor" {
  name              = "/aws/lambda/${var.project_name}-processor-${var.environment}"
  retention_in_days = 30  # don't keep logs forever — costs money
}

# -------------------------------------------------------
# IAM ROLE — Writer Lambda identity
# -------------------------------------------------------
resource "aws_iam_role" "writer_lambda_role" {
  name = "${var.project_name}-writer-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "writer_basic_execution" {
  role       = aws_iam_role.writer_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "writer_lambda_policy" {
  name = "${var.project_name}-writer-policy-${var.environment}"
  role = aws_iam_role.writer_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Read AND delete messages from SQS
        # Delete is required — Lambda must remove messages after processing
        Sid    = "ConsumeFromSQS"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility"
        ]
        Resource = var.sqs_queue_arn
      },
      {
        # Write records to DynamoDB
        Sid    = "WriteToDynamoDB"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem"
        ]
        Resource = var.dynamodb_table_arn
      },
      {
        Sid      = "PushCloudWatchMetrics"
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData"]
        Resource = "*"
      }
    ]
  })
}

# -------------------------------------------------------
# PACKAGE + DEPLOY WRITER LAMBDA
# -------------------------------------------------------
data "archive_file" "writer_lambda" {
  type        = "zip"
  source_dir  = "${path.root}/../src/writer"
  output_path = "${path.root}/../src/writer/writer_lambda.zip"
}

resource "aws_lambda_function" "writer" {
  function_name = "${var.project_name}-writer-${var.environment}"
  description   = "Reads from SQS, writes records to DynamoDB"

  filename         = data.archive_file.writer_lambda.output_path
  source_code_hash = data.archive_file.writer_lambda.output_base64sha256

  runtime     = "python3.11"
  handler     = "handler.handler"
  role        = aws_iam_role.writer_lambda_role.arn
  memory_size = 256
  timeout     = 300

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = var.dynamodb_table_name
      ENVIRONMENT         = var.environment
      PROJECT_NAME        = var.project_name
    }
  }

  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.writer.name
  }

  depends_on = [
    aws_iam_role_policy_attachment.writer_basic_execution,
    aws_cloudwatch_log_group.writer,
  ]
}

# SQS → Lambda #2 trigger
# This is what makes SQS automatically invoke the writer
resource "aws_lambda_event_source_mapping" "sqs_to_writer" {
  event_source_arn                   = var.sqs_queue_arn
  function_name                      = aws_lambda_function.writer.arn
  batch_size                         = 10   # process up to 10 records at once
  #maximum_batching_window_in_seconds = 5    # wait up to 5s to fill a batch

  # Enables partial batch failure reporting
  # Matches what handler.py returns in batchItemFailures
  function_response_types = ["ReportBatchItemFailures"]
}

resource "aws_cloudwatch_log_group" "writer" {
  name              = "/aws/lambda/${var.project_name}-writer-${var.environment}"
  retention_in_days = 30
}
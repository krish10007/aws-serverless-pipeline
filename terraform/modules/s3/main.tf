# -------------------------------------------------------
# DATA BUCKET — where you upload CSV/JSON files
# -------------------------------------------------------
resource "aws_s3_bucket" "data_bucket" {
  # Bucket name must be globally unique across all AWS accounts
  bucket = "${var.project_name}-data-${var.environment}-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "${var.project_name}-data-bucket"
  }
}

# Get current AWS account ID — used to make bucket name unique
data "aws_caller_identity" "current" {}

# Block all public access — this bucket is private, always
resource "aws_s3_bucket_public_access_block" "data_bucket" {
  bucket = aws_s3_bucket.data_bucket.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# Enable versioning — lets you recover accidentally overwritten files
resource "aws_s3_bucket_versioning" "data_bucket" {
  bucket = aws_s3_bucket.data_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption — all objects encrypted at rest
resource "aws_s3_bucket_server_side_encryption_configuration" "data_bucket" {
  bucket = aws_s3_bucket.data_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Lifecycle rule — move old files to cheaper storage after 90 days
# This is what production buckets do to control storage costs
resource "aws_s3_bucket_lifecycle_configuration" "data_bucket" {
  bucket = aws_s3_bucket.data_bucket.id

  rule {
    id     = "archive-old-files"
    status = "Enabled"

    filter {
      prefix = ""  # applies to all objects
    }

    # After 90 days move to Infrequent Access (cheaper, same durability)
    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    # After 365 days move to Glacier (very cheap, slow retrieval)
    transition {
      days          = 365
      storage_class = "GLACIER"
    }
  }
}

# -------------------------------------------------------
# S3 → LAMBDA EVENT NOTIFICATION
# S3 will call Lambda when a .csv or .json file is uploaded
# -------------------------------------------------------

# This permission lets S3 invoke the Lambda function
# Without this, S3 fires the event but Lambda rejects it (403)
resource "aws_lambda_permission" "allow_s3_invoke" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = var.processor_lambda_arn
  principal     = "s3.amazonaws.com"

  # Restrict to only THIS bucket — not any S3 bucket in your account
  source_arn = aws_s3_bucket.data_bucket.arn
}

# The actual event notification — tells S3 what to call and when
resource "aws_s3_bucket_notification" "data_bucket" {
  bucket = aws_s3_bucket.data_bucket.id

  lambda_function {
    lambda_function_arn = var.processor_lambda_arn
    events              = ["s3:ObjectCreated:*"]  # fires on any upload

    # Only trigger for CSV files in the raw/ prefix
    filter_prefix = "raw/"
    filter_suffix = ".csv"
  }

  lambda_function {
    lambda_function_arn = var.processor_lambda_arn
    events              = ["s3:ObjectCreated:*"]

    # Also trigger for JSON files in the raw/ prefix
    filter_prefix = "raw/"
    filter_suffix = ".json"
  }

  # Lambda must exist before S3 can set up the notification
  depends_on = [aws_lambda_permission.allow_s3_invoke]
}
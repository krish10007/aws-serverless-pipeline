variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "sqs_queue_url" {
  description = "URL of the SQS queue processor Lambda writes to"
  type        = string
}

variable "sqs_queue_arn" {
  description = "ARN of the SQS queue — needed for IAM permissions"
  type        = string
}

variable "data_bucket_arn" {
  description = "ARN of the S3 data bucket — needed for IAM read permissions"
  type        = string
}

variable "dynamodb_table_name" {
  description = "DynamoDB table name — passed to writer Lambda as env var"
  type        = string
}

variable "dynamodb_table_arn" {
  description = "DynamoDB table ARN — needed for IAM permissions"
  type        = string
}
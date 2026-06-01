variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "alert_email" {
  description = "Email address that receives failure alerts"
  type        = string
}

variable "dlq_alarm_name" {
  description = "Name of the DLQ CloudWatch alarm — we attach SNS to it"
  type        = string
}

variable "processor_lambda_name" {
  description = "Processor Lambda name — for error rate alarm"
  type        = string
}

variable "writer_lambda_name" {
  description = "Writer Lambda name — for error rate alarm"
  type        = string
}

variable "aws_region" {
  type = string
}

variable "dynamodb_table_name" {
  type        = string
  description = "DynamoDB table name for dashboard widgets"
}

variable "processor_log_group_name" {
  description = "Processor Lambda log group — ensures it exists before metric filter"
  type        = string
}

variable "writer_log_group_name" {
  description = "Writer Lambda log group — ensures it exists before metric filter"
  type        = string
}
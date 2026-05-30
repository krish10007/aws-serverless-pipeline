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
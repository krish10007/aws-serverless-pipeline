variable "project_name" {
  description = "Project name used as resource prefix"
  type        = string
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "processor_lambda_arn" {
  description = "ARN of the processor Lambda function S3 will invoke"
  type        = string
}
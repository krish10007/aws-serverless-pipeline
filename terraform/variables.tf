variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used as prefix for all resources"
  type        = string
  default     = "serverless-pipeline"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "prod"
}

variable "alert_email" {
  description = "Email address for SNS failure alerts"
  type        = string
}
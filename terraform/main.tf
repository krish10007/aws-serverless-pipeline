# -------------------------------------------------------
# ROOT MAIN.TF
# Calls each module and wires outputs between them
# -------------------------------------------------------

module "dynamodb" {
  source = "./modules/dynamodb"

  project_name = var.project_name
  environment  = var.environment
}

module "sqs" {
  source = "./modules/sqs"

  project_name = var.project_name
  environment  = var.environment
}

module "lambda" {
  source = "./modules/lambda"

  project_name        = var.project_name
  environment         = var.environment
  sqs_queue_url       = module.sqs.queue_url
  sqs_queue_arn       = module.sqs.queue_arn
  data_bucket_arn     = module.s3.bucket_arn
  dynamodb_table_name = module.dynamodb.table_name
  dynamodb_table_arn  = module.dynamodb.table_arn
}

module "s3" {
  source = "./modules/s3"

  project_name         = var.project_name
  environment          = var.environment
  aws_region           = var.aws_region
  processor_lambda_arn = module.lambda.processor_lambda_arn
}

module "monitoring" {
  source = "./modules/monitoring"

  project_name          = var.project_name
  environment           = var.environment
  alert_email           = var.alert_email
  aws_region            = var.aws_region
  dlq_alarm_name        = module.sqs.dlq_alarm_name
  processor_lambda_name = module.lambda.processor_lambda_name
  writer_lambda_name    = module.lambda.writer_lambda_name
  dynamodb_table_name   = module.dynamodb.table_name
}
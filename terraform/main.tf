# -------------------------------------------------------
# ROOT MAIN.TF
# Calls each module and wires outputs between them
# -------------------------------------------------------


module "sqs" {
  source = "./modules/sqs"

  project_name = var.project_name
  environment  = var.environment
}

module "lambda" {
  source = "./modules/lambda"

  project_name    = var.project_name
  environment     = var.environment
  sqs_queue_url   = module.sqs.queue_url
  sqs_queue_arn   = module.sqs.queue_arn
  data_bucket_arn = module.s3.bucket_arn
}

module "s3" {
  source = "./modules/s3"

  project_name         = var.project_name
  environment          = var.environment
  aws_region           = var.aws_region
  processor_lambda_arn = module.lambda.processor_lambda_arn
}
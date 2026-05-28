# -------------------------------------------------------
# ROOT MAIN.TF
# Calls each module and wires outputs between them
# -------------------------------------------------------


module "lambda" {
  source = "./modules/lambda"

  project_name    = var.project_name
  environment     = var.environment
  sqs_queue_url   = module.sqs.queue_url    # comes from SQS module (next)
  sqs_queue_arn   = module.sqs.queue_arn    # comes from SQS module (next)
  data_bucket_arn = module.s3.bucket_arn    # comes from S3 module
}

module "s3" {
  source = "./modules/s3"

  project_name         = var.project_name
  environment          = var.environment
  aws_region           = var.aws_region
  processor_lambda_arn = module.lambda.processor_lambda_arn  # comes from Lambda module
}
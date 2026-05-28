# -------------------------------------------------------
# ROOT MAIN.TF
# Calls each module and wires outputs between them
# -------------------------------------------------------

module "s3" {
  source = "./modules/s3"

  project_name         = var.project_name
  environment          = var.environment
  aws_region           = var.aws_region
  processor_lambda_arn = module.lambda.processor_lambda_arn  # comes from Lambda module later
}
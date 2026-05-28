output "data_bucket_name" {
  description = "Upload CSV/JSON files here to trigger the pipeline"
  value       = module.s3.bucket_name
}
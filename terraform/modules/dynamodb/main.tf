resource "aws_dynamodb_table" "pipeline_records" {
  name         = "${var.project_name}-records-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"  # on-demand, no capacity planning needed

  # Primary key — every item must have these two attributes
  hash_key  = "record_id"   # partition key
  range_key = "ingested_at" # sort key

  # Attribute definitions — only define key attributes here
  # Non-key attributes don't need to be declared (that's the NoSQL flexibility)
  attribute {
    name = "record_id"
    type = "S"  # S = String, N = Number, B = Binary
  }

  attribute {
    name = "ingested_at"
    type = "S"
  }

  # Point-in-time recovery — lets you restore the table
  # to any second in the last 35 days
  # This is what "production-grade" means for a database
  point_in_time_recovery {
    enabled = true
  }

  # Encrypt all data at rest using AWS managed key
  server_side_encryption {
    enabled = true
  }

  # TTL — automatically delete old records after 90 days
  # Keeps the table lean without manual cleanup jobs
  ttl {
    attribute_name = "expires_at"  # Lambda #2 will set this field
    enabled        = true
  }

  tags = {
    Name = "${var.project_name}-records"
  }
}
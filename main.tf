locals {
  name = "${var.project_name}-${var.environment}"

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Repository  = "example-org/orders-serverless-api"
  }
}

# -----------------------------------------------------------------------------
# Database (DynamoDB)
# -----------------------------------------------------------------------------

resource "aws_dynamodb_table" "this" {
  name         = "${local.name}-data"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"
  range_key    = "sk"

  deletion_protection_enabled = var.environment == "production"

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }
}

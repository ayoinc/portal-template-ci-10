provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.tags
  }
}

# Web ACLs for CloudFront are created in us-east-1 whatever the region of the API.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = local.tags
  }
}

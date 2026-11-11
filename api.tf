# -----------------------------------------------------------------------------
# HTTP API
# -----------------------------------------------------------------------------

resource "aws_apigatewayv2_api" "this" {
  name          = "${local.name}-api"
  description   = "HTTP API of ${var.project_name} (${var.environment})"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = var.cors_allowed_origins
    allow_methods = ["*"]
    allow_headers = ["authorization", "content-type", "x-amz-date", "x-amz-security-token", "x-api-key"]
    max_age       = 300
  }
}

module "api_logs" {
  source = "git::https://github.com/ayoinc/cloud-sandbox-backstage.git//catalog/terraform-modules/aws/resources/monitoring/cloudwatch?ref=83f9ff7222d2731d5cc0da4ab1fc1f7c46da3693"

  project_name      = var.project_name
  environment       = var.environment
  log_group_name    = "/aws/apigateway/${local.name}-api"
  retention_in_days = var.log_retention_days
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = module.api_logs.log_group_arn
    format = jsonencode({
      requestId        = "$context.requestId"
      requestTime      = "$context.requestTime"
      sourceIp         = "$context.identity.sourceIp"
      httpMethod       = "$context.httpMethod"
      path             = "$context.path"
      routeKey         = "$context.routeKey"
      status           = "$context.status"
      responseLength   = "$context.responseLength"
      responseLatency  = "$context.responseLatency"
      integrationError = "$context.integrationErrorMessage"
      authorizerError  = "$context.authorizer.error"
    })
  }

  default_route_settings {
    detailed_metrics_enabled = true
    throttling_rate_limit    = var.throttle_rate_limit
    throttling_burst_limit   = var.throttle_burst_limit
  }
}

resource "aws_apigatewayv2_integration" "function" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_alias.live.invoke_arn
  payload_format_version = "2.0"
  timeout_milliseconds   = min(var.timeout, 30) * 1000
}

resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.function.id}"

  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.this.id
}

# Browsers send preflight requests without credentials. This route keeps them
# away from the authorization of the $default route; API Gateway answers them
# from the CORS configuration of the API.
resource "aws_apigatewayv2_route" "preflight" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "OPTIONS /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.function.id}"
}

resource "aws_lambda_permission" "api" {
  statement_id  = "AllowApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = module.function.function_name
  qualifier     = aws_lambda_alias.live.name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}

resource "aws_apigatewayv2_authorizer" "this" {
  api_id           = aws_apigatewayv2_api.this.id
  name             = "cognito"
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    issuer   = "https://${aws_cognito_user_pool.this.endpoint}"
    audience = [aws_cognito_user_pool_client.this.id]
  }
}

# -----------------------------------------------------------------------------
# Users (Cognito)
# -----------------------------------------------------------------------------

resource "aws_cognito_user_pool" "this" {
  name                     = "${local.name}-users"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  mfa_configuration        = "OPTIONAL"
  deletion_protection      = var.environment == "production" ? "ACTIVE" : "INACTIVE"

  software_token_mfa_configuration {
    enabled = true
  }

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 7
  }

  admin_create_user_config {
    allow_admin_create_user_only = !var.allow_self_sign_up
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }
}

# Public client for applications that sign users in (no client secret).
resource "aws_cognito_user_pool_client" "this" {
  name                          = "${local.name}-client"
  user_pool_id                  = aws_cognito_user_pool.this.id
  generate_secret               = false
  explicit_auth_flows           = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  prevent_user_existence_errors = "ENABLED"
}

# -----------------------------------------------------------------------------
# Web application firewall
# -----------------------------------------------------------------------------

module "waf" {
  source = "git::https://github.com/ayoinc/cloud-sandbox-backstage.git//catalog/terraform-modules/aws/resources/security/waf?ref=83f9ff7222d2731d5cc0da4ab1fc1f7c46da3693"

  providers = {
    aws = aws.us_east_1
  }

  project_name = var.project_name
  environment  = var.environment
  name         = "api"
  scope        = "CLOUDFRONT"
}

# A web ACL cannot be attached to an HTTP API. Clients call this CloudFront
# distribution, which applies the web ACL and passes every request on to the
# API without caching.
data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

resource "aws_cloudfront_distribution" "api" {
  enabled         = true
  comment         = "${local.name} API"
  is_ipv6_enabled = true
  http_version    = "http2and3"
  web_acl_id      = module.waf.web_acl_arn

  origin {
    origin_id   = "api"
    domain_name = trimprefix(aws_apigatewayv2_api.this.api_endpoint, "https://")

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id         = "api"
    viewer_protocol_policy   = "https-only"
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
    compress                 = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

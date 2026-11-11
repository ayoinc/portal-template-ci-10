locals {
  function_name         = "${local.name}-api"
  supplied_package_hash = var.deployment_package == null ? null : filebase64sha256(var.deployment_package)
}

# Placeholder handler, deployed until a package is supplied through
# var.deployment_package or var.deployment_package_s3.
data "archive_file" "placeholder" {
  count = local.use_placeholder ? 1 : 0

  type             = "zip"
  source_file      = "${path.module}/placeholder/index.mjs"
  output_path      = "${path.module}/build/placeholder.zip"
  output_file_mode = "0644"
}

locals {
  use_placeholder = var.deployment_package == null && var.deployment_package_s3 == null
  package_file    = local.use_placeholder ? data.archive_file.placeholder[0].output_path : var.deployment_package
  package_hash    = local.use_placeholder ? data.archive_file.placeholder[0].output_base64sha256 : local.supplied_package_hash
}

# -----------------------------------------------------------------------------
# Execution role
# -----------------------------------------------------------------------------

module "function_role" {
  source = "git::https://github.com/ayoinc/cloud-sandbox-backstage.git//catalog/terraform-modules/aws/resources/core/iam-role?ref=83f9ff7222d2731d5cc0da4ab1fc1f7c46da3693"

  name             = "${local.name}-function"
  description      = "Execution role of the ${local.function_name} function"
  trusted_services = ["lambda.amazonaws.com"]

  inline_policies = {
    logs = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${module.monitoring.log_group_arn}:*"
      }]
    })

    tracing = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect   = "Allow"
        Action   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords", "xray:GetSamplingRules", "xray:GetSamplingTargets"]
        Resource = "*"
      }]
    })

    metrics = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect    = "Allow"
        Action    = "cloudwatch:PutMetricData"
        Resource  = "*"
        Condition = { StringEquals = { "cloudwatch:namespace" = local.metrics_namespace } }
      }]
    })

    table = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect = "Allow"
        Action = [
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:ConditionCheckItem",
          "dynamodb:DeleteItem",
          "dynamodb:DescribeTable",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:UpdateItem",
        ]
        Resource = [aws_dynamodb_table.this.arn, "${aws_dynamodb_table.this.arn}/index/*"]
      }]
    })
  }
}

# -----------------------------------------------------------------------------
# Function
# -----------------------------------------------------------------------------

module "function" {
  source = "git::https://github.com/ayoinc/cloud-sandbox-backstage.git//catalog/terraform-modules/aws/resources/compute/lambda?ref=83f9ff7222d2731d5cc0da4ab1fc1f7c46da3693"

  function_name = local.function_name
  description   = "API handler of ${var.project_name} (${var.environment})"
  role_arn      = module.function_role.role_arn
  runtime       = var.function_runtime
  handler       = var.function_handler
  architectures = [var.function_architecture]
  memory_size   = var.memory_size
  timeout       = var.timeout

  filename          = local.package_file
  source_code_hash  = local.package_hash
  s3_bucket         = try(var.deployment_package_s3.bucket, null)
  s3_key            = try(var.deployment_package_s3.key, null)
  s3_object_version = try(var.deployment_package_s3.object_version, null)

  # Every change of the code or the configuration becomes a numbered version.
  publish = true

  tracing_config = {
    mode = "Active"
  }

  environment_variables = merge(
    {
      PROJECT_NAME = var.project_name
      ENVIRONMENT  = var.environment
    },
    { METRICS_NAMESPACE = local.metrics_namespace },
    { TABLE_NAME = aws_dynamodb_table.this.name },
    var.function_environment,
  )

  # The policies of the role must be in place before Lambda creates the function.
  depends_on = [module.function_role]
}

# -----------------------------------------------------------------------------
# Alias and traffic shifting
# -----------------------------------------------------------------------------

# The API calls the alias. Terraform publishes new versions but leaves the alias
# alone after creating it: CodeDeploy moves it to the new version.
resource "aws_lambda_alias" "live" {
  name             = "live"
  description      = "Version that receives the traffic of the API"
  function_name    = module.function.function_name
  function_version = module.function.version

  lifecycle {
    ignore_changes = [function_version, routing_config]
  }
}

resource "aws_codedeploy_app" "function" {
  name             = local.function_name
  compute_platform = "Lambda"
}

module "codedeploy_role" {
  source = "git::https://github.com/ayoinc/cloud-sandbox-backstage.git//catalog/terraform-modules/aws/resources/core/iam-role?ref=83f9ff7222d2731d5cc0da4ab1fc1f7c46da3693"

  name             = "${local.name}-codedeploy"
  description      = "Lets CodeDeploy shift the traffic of the ${local.function_name} function"
  trusted_services = ["codedeploy.amazonaws.com"]

  inline_policies = {
    alias = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect   = "Allow"
        Action   = ["lambda:GetAlias", "lambda:UpdateAlias", "lambda:GetProvisionedConcurrencyConfig"]
        Resource = [module.function.function_arn, "${module.function.function_arn}:*"]
      }]
    })

    alarms = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect   = "Allow"
        Action   = "cloudwatch:DescribeAlarms"
        Resource = "*"
      }]
    })
  }
}

resource "aws_codedeploy_deployment_group" "function" {
  app_name               = aws_codedeploy_app.function.name
  deployment_group_name  = local.function_name
  service_role_arn       = module.codedeploy_role.role_arn
  deployment_config_name = var.deployment_config_name

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }

  # A deployment stops and rolls back when the function starts to fail.
  alarm_configuration {
    enabled = true
    alarms  = ["${local.name}-function-errors"]
  }

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
  }

  depends_on = [module.codedeploy_role, module.monitoring]
}

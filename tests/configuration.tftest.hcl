# Plans the configuration against a mocked AWS provider. No credentials are
# used and nothing is created.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }
}

mock_provider "aws" {
  alias = "us_east_1"
}

run "chosen_options" {
  command = plan

  assert {
    condition = (
      module.function.function_name == "orders-dev-api" &&
      module.monitoring.log_group_name == "/aws/lambda/orders-dev-api" &&
      aws_lambda_alias.live.name == "live"
    )
    error_message = "The function, its log group and the alias do not have the expected names."
  }

  assert {
    condition     = length(data.archive_file.placeholder) == 1
    error_message = "The placeholder handler must be packaged while no deployment package is supplied."
  }

  assert {
    condition = (
      aws_apigatewayv2_api.this.protocol_type == "HTTP" &&
      aws_apigatewayv2_route.default.authorization_type == "JWT" &&
      length(aws_apigatewayv2_api.this.cors_configuration) == 1
    )
    error_message = "The HTTP API does not have the chosen authorization and CORS settings."
  }

  assert {
    condition = (
      aws_apigatewayv2_stage.default.default_route_settings[0].throttling_rate_limit == var.throttle_rate_limit &&
      aws_apigatewayv2_stage.default.default_route_settings[0].throttling_burst_limit == var.throttle_burst_limit
    )
    error_message = "The stage does not apply the throttling limits."
  }

  assert {
    condition = (
      aws_dynamodb_table.this.name == "orders-dev-data" &&
      aws_dynamodb_table.this.point_in_time_recovery[0].enabled &&
      aws_dynamodb_table.this.server_side_encryption[0].enabled
    )
    error_message = "The DynamoDB table must be encrypted and have point-in-time recovery."
  }

  assert {
    condition = (
      aws_codedeploy_deployment_group.function.deployment_config_name == "CodeDeployDefault.LambdaCanary10Percent5Minutes" &&
      aws_codedeploy_app.function.compute_platform == "Lambda"
    )
    error_message = "CodeDeploy does not use the deployment configuration of the chosen strategy."
  }

  assert {
    condition     = length(module.monitoring.alarm_arns) == 4
    error_message = "The alarms do not follow the alarm option."
  }
}

# The longest project name the portal accepts, in the environment with the
# longest name.
run "longest_names" {
  command = plan

  variables {
    project_name = "a23456789-b23456789-c234"
    environment  = "production"
  }

  assert {
    condition     = length(module.function_role.role_name) <= 64 && length(module.function.function_name) <= 64
    error_message = "The names of the function and its role exceed 64 characters."
  }
}

run "supplied_package" {
  command = plan

  variables {
    deployment_package_s3 = {
      bucket = "example-artifacts"
      key    = "orders/function.zip"
    }
  }

  assert {
    condition     = length(data.archive_file.placeholder) == 0
    error_message = "The placeholder handler must not be packaged when a deployment package is supplied."
  }
}

# Log group of the function, metric filters on its log lines and the alarms of the function and the API.
module "monitoring" {
  source = "git::https://github.com/ayoinc/cloud-sandbox-backstage.git//catalog/terraform-modules/aws/resources/monitoring/cloudwatch?ref=83f9ff7222d2731d5cc0da4ab1fc1f7c46da3693"

  project_name      = var.project_name
  environment       = var.environment
  log_group_name    = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_days

  log_metric_filters = [
    {
      name             = "${local.name}-logged-errors"
      pattern          = "?ERROR ?Error ?Exception"
      metric_name      = "LoggedErrors"
      metric_namespace = local.metrics_namespace
      metric_value     = "1"
    },
    {
      name             = "${local.name}-timeouts"
      pattern          = "\"Task timed out\""
      metric_name      = "Timeouts"
      metric_namespace = local.metrics_namespace
      metric_value     = "1"
    },
  ]

  alarms = [
    {
      name                = "${local.name}-function-errors"
      comparison_operator = "GreaterThanThreshold"
      evaluation_periods  = 1
      metric_name         = "Errors"
      namespace           = "AWS/Lambda"
      period              = 300
      statistic           = "Sum"
      threshold           = 0
      alarm_actions       = [module.alarm_topic.topic_arn]
      dimensions          = { FunctionName = local.function_name }
    },
    {
      name                = "${local.name}-function-throttles"
      comparison_operator = "GreaterThanThreshold"
      evaluation_periods  = 1
      metric_name         = "Throttles"
      namespace           = "AWS/Lambda"
      period              = 300
      statistic           = "Sum"
      threshold           = 0
      alarm_actions       = [module.alarm_topic.topic_arn]
      dimensions          = { FunctionName = local.function_name }
    },
    {
      name                = "${local.name}-api-5xx"
      comparison_operator = "GreaterThanThreshold"
      evaluation_periods  = 1
      metric_name         = "5xx"
      namespace           = "AWS/ApiGateway"
      period              = 300
      statistic           = "Sum"
      threshold           = 0
      alarm_actions       = [module.alarm_topic.topic_arn]
      dimensions          = local.api_metric_dimensions
    },
    {
      name                = "${local.name}-api-latency"
      comparison_operator = "GreaterThanThreshold"
      evaluation_periods  = 3
      metric_name         = "Latency"
      namespace           = "AWS/ApiGateway"
      period              = 300
      statistic           = "Average"
      threshold           = var.alarm_latency_threshold_ms
      alarm_actions       = [module.alarm_topic.topic_arn]
      dimensions          = local.api_metric_dimensions
    },
  ]
}

locals {
  # Namespace of the metric filters and of the metrics the function publishes
  # itself; the function reads it from METRICS_NAMESPACE.
  metrics_namespace = "${var.project_name}/${var.environment}"
}

locals {
  api_metric_dimensions = {
    ApiId = aws_apigatewayv2_api.this.id
  }
}

# Topic the alarms notify.
module "alarm_topic" {
  source = "git::https://github.com/ayoinc/cloud-sandbox-backstage.git//catalog/terraform-modules/aws/resources/messaging/sns?ref=83f9ff7222d2731d5cc0da4ab1fc1f7c46da3693"

  project_name         = var.project_name
  environment          = var.environment
  topic_name           = "alarms"
  allowed_aws_services = ["cloudwatch.amazonaws.com"]
  subscriptions        = var.alarm_email == null ? [] : [{ protocol = "email", endpoint = var.alarm_email }]
}

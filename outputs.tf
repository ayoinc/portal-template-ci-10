output "api_endpoint" {
  description = "URL that clients call."
  value       = "https://${aws_cloudfront_distribution.api.domain_name}"
}

output "api_id" {
  description = "Identifier of the API."
  value       = aws_apigatewayv2_api.this.id
}

output "api_origin_endpoint" {
  description = "URL of the HTTP API behind CloudFront. Requests sent here do not pass the web ACL."
  value       = aws_apigatewayv2_api.this.api_endpoint
}

output "cloudfront_distribution_id" {
  description = "Identifier of the CloudFront distribution in front of the API."
  value       = aws_cloudfront_distribution.api.id
}

output "web_acl_arn" {
  description = "ARN of the web ACL that filters requests to the API."
  value       = module.waf.web_acl_arn
}

output "cognito_user_pool_id" {
  description = "Identifier of the Cognito user pool whose users may call the API."
  value       = aws_cognito_user_pool.this.id
}

output "cognito_client_id" {
  description = "Identifier of the app client that signs users in."
  value       = aws_cognito_user_pool_client.this.id
}

output "jwt_issuer" {
  description = "Issuer of the tokens the API accepts."
  value       = "https://${aws_cognito_user_pool.this.endpoint}"
}

output "function_name" {
  description = "Name of the Lambda function."
  value       = module.function.function_name
}

output "function_arn" {
  description = "ARN of the Lambda function."
  value       = module.function.function_arn
}

output "function_version" {
  description = "Newest published version of the function."
  value       = module.function.version
}

output "function_alias_arn" {
  description = "ARN of the alias that the API calls."
  value       = aws_lambda_alias.live.arn
}

output "function_role_arn" {
  description = "ARN of the execution role of the function."
  value       = module.function_role.role_arn
}

output "function_log_group" {
  description = "CloudWatch log group of the function."
  value       = module.monitoring.log_group_name
}

output "codedeploy_application" {
  description = "CodeDeploy application that shifts traffic to a new function version."
  value       = aws_codedeploy_app.function.name
}

output "codedeploy_deployment_group" {
  description = "CodeDeploy deployment group of the function."
  value       = aws_codedeploy_deployment_group.function.deployment_group_name
}

output "table_name" {
  description = "Name of the DynamoDB table."
  value       = aws_dynamodb_table.this.name
}

output "metrics_namespace" {
  description = "CloudWatch namespace of the custom metrics."
  value       = local.metrics_namespace
}

output "alarm_topic_arn" {
  description = "ARN of the SNS topic the alarms notify."
  value       = module.alarm_topic.topic_arn
}

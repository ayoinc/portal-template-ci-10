variable "project_name" {
  description = "Name of the API. Resource names start with <project_name>-<environment>."
  type        = string
  default     = "orders"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_name)) && length(var.project_name) <= 24
    error_message = "project_name must be at most 24 lowercase letters, digits and hyphens, start with a letter and end with a letter or digit."
  }
}

variable "environment" {
  description = "Deployment environment."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "environment must be dev, staging or production."
  }
}

variable "aws_region" {
  description = "Region the resources are created in."
  type        = string
  default     = "eu-west-1"
}

variable "function_runtime" {
  description = "Lambda runtime identifier of the function."
  type        = string
  default     = "nodejs24.x"
}

variable "function_handler" {
  description = "Entry point of the function inside the deployment package."
  type        = string
  default     = "index.handler"
}

variable "function_architecture" {
  description = "Instruction set the deployment package is built for."
  type        = string
  default     = "x86_64"

  validation {
    condition     = contains(["x86_64", "arm64"], var.function_architecture)
    error_message = "function_architecture must be x86_64 or arm64."
  }
}

variable "memory_size" {
  description = "Memory of the function in MB."
  type        = number
  default     = 256

  validation {
    condition     = var.memory_size >= 128 && var.memory_size <= 10240
    error_message = "memory_size must be between 128 and 10240 MB."
  }
}

variable "timeout" {
  description = "Timeout of the function in seconds. API Gateway stops waiting after 30 seconds whatever this value is."
  type        = number
  default     = 30

  validation {
    condition     = var.timeout >= 1 && var.timeout <= 900
    error_message = "timeout must be between 1 and 900 seconds."
  }
}

variable "deployment_package" {
  description = "Path to the zip file with the function code. When this and deployment_package_s3 are both null the placeholder handler in placeholder/ is deployed."
  type        = string
  default     = null
}

variable "deployment_package_s3" {
  description = "Location of the zip file with the function code in S3. Use a new key or pass object_version for every build so that a change is detected."
  type = object({
    bucket         = string
    key            = string
    object_version = optional(string)
  })
  default = null

  validation {
    condition     = var.deployment_package == null || var.deployment_package_s3 == null
    error_message = "Set only one of deployment_package and deployment_package_s3."
  }
}

variable "function_environment" {
  description = "Additional environment variables for the function. Do not put secrets here: they end up in the Terraform state."
  type        = map(string)
  default     = {}
}

variable "log_retention_days" {
  description = "Days to keep the logs of the function and the API."
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a retention period that CloudWatch Logs supports (for example 7, 14, 30, 60, 90, 180 or 365)."
  }
}

variable "cors_allowed_origins" {
  description = "Origins that browsers may call the API from."
  type        = list(string)
  default     = ["*"]
}

variable "throttle_rate_limit" {
  description = "Steady-state requests per second the API accepts."
  type        = number
  default     = 1000

  validation {
    condition     = var.throttle_rate_limit >= 1
    error_message = "throttle_rate_limit must be at least 1."
  }
}

variable "throttle_burst_limit" {
  description = "Requests the API accepts in a burst above the steady-state rate."
  type        = number
  default     = 2000

  validation {
    condition     = var.throttle_burst_limit >= 1
    error_message = "throttle_burst_limit must be at least 1."
  }
}

variable "allow_self_sign_up" {
  description = "Let users register in the Cognito user pool themselves. When false only administrators create users."
  type        = bool
  default     = false
}

variable "alarm_email" {
  description = "Address that receives alarm notifications. The recipient has to confirm the subscription. null creates the topic without a subscription."
  type        = string
  default     = null
}

variable "alarm_latency_threshold_ms" {
  description = "Average API latency in milliseconds over five minutes that raises the latency alarm."
  type        = number
  default     = 2000
}

variable "deployment_config_name" {
  description = "CodeDeploy deployment configuration that moves traffic to a new function version."
  type        = string
  default     = "CodeDeployDefault.LambdaCanary10Percent5Minutes"
}

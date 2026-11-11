# Infrastructure

The Terraform configuration in the root of the repository creates the
resources below in `eu-west-1`. Names start with
`orders-dev`.

| Path | Contents |
| ---- | -------- |
| `main.tf` | Names and tags, database |
| `function.tf` | Function, its execution role, the alias `live`, CodeDeploy |
| `api.tf` | HTTP API, authentication, web ACL, CloudFront distribution |
| `monitoring.tf` | Log group of the function, metric filters, alarms and their topic |
| `variables.tf` | Inputs; the values chosen in the portal are the defaults |
| `outputs.tf` | Outputs |
| `tests/` | Plan of the configuration against a mocked AWS provider, run by `terraform test` |
| `placeholder/` | Handler that is deployed until a function package is supplied |
| `scripts/shift-traffic.sh` | Moves traffic to a new function version with CodeDeploy |

Shared modules are taken from
`github.com/ayoinc/cloud-sandbox-backstage` at a pinned commit.

## Function

- Lambda function `orders-dev-api`, runtime
  `nodejs24.x`, 256 MB, timeout 30 s.
- An execution role that may write to the log group of the function, send traces to X-Ray, publish metrics in the namespace `orders/dev`, read and write the DynamoDB table and nothing else.
- Log group `/aws/lambda/orders-dev-api`, kept for 30 days.
- Every apply that changes the code or the configuration publishes a new
  function version. The API calls the alias `live`.
- Deployment strategy `canary`: a CodeDeploy application and deployment group
  move the alias to a new version with
  `CodeDeployDefault.LambdaCanary10Percent5Minutes` (10 % of the traffic for five
  minutes, then the rest). See [Traffic shifting](#traffic-shifting).

The function receives these environment variables:

| Variable | Value |
| -------- | ----- |
| `PROJECT_NAME`, `ENVIRONMENT` | Project name and environment |
| `METRICS_NAMESPACE` | CloudWatch namespace the function may publish metrics in |
| `TABLE_NAME` | DynamoDB table |

Add your own with the variable `function_environment`.

## Function package

The repository holds no application code. The code is built elsewhere and
handed to Terraform as a zip file in one of two ways:

- `deployment_package`: path to a zip file on the machine that runs Terraform.
- `deployment_package_s3`: `{ bucket = "...", key = "..." }` of a zip file in
  S3, optionally with `object_version`. Use this when Terraform runs in a
  pipeline: upload the package from the application's pipeline and commit the
  new key or object version to `terraform.tfvars` here. Terraform only notices
  a new package when the key or the object version changes.

Set `function_handler` to the entry point of your package (default
`index.handler`) and `function_architecture` to `arm64` if it is built for
Graviton.

While neither variable is set, Terraform packages the placeholder handler in
`placeholder/` and deploys it, so the first apply works without a build. The
placeholder answers every request with status 200 and a JSON body, in the response format of
HTTP API payload version 2.0.

The function is called with HTTP API events of payload format 2.0. API Gateway
waits at most 30 seconds for it.

## API

- API Gateway HTTP API with one `$default` route that sends every request to
  the function, and a `$default` stage that deploys changes automatically.
- Access logs in `/aws/apigateway/orders-dev-api`, kept for 30 days.
- CORS: API Gateway answers preflight requests and adds the CORS headers for
  the origins in `cors_allowed_origins` (default: any).
- Throttling: 1000 requests per second with a burst of 2000 for the whole
  stage (`throttle_rate_limit`, `throttle_burst_limit`).
- Tracing: the function sends traces to X-Ray. HTTP APIs cannot take part in
  X-Ray traces, so a trace starts at the function.

### Authentication

A Cognito user pool (`orders-dev-users`, sign-in with e-mail address, optional
TOTP as second factor) and a public app client are created. Users are created
by an administrator unless `allow_self_sign_up` is `true`.
A JWT authorizer accepts ID and access tokens of the pool in the
`Authorization` header.

### Web application firewall

A web ACL with the AWS managed rule groups Common, Known Bad Inputs, SQL
injection, Linux and Amazon IP reputation list filters the requests. The Common
rule group blocks request bodies larger than 8 KB among other things; adjust
`managed_rule_groups` of the module `waf` in `api.tf` if the API needs
different rules.

A web ACL cannot be attached to an HTTP API. A CloudFront distribution is
placed in front of the API instead and carries the web ACL (created in
us-east-1, as CloudFront requires). It forwards every request without caching.
Clients must call the output `api_endpoint` (the `cloudfront.net` address). The
address of the API itself (`api_origin_endpoint`) stays reachable and is not
protected by the web ACL, so treat it as internal. The `cloudfront.net`
certificate accepts TLS 1.0 and later; a stricter policy needs a custom domain
with its own certificate, which this configuration does not set up.

## Data

- DynamoDB table `orders-dev-data` with partition key `pk` and sort key `sk`
  (strings), on-demand capacity, encryption at rest and point-in-time recovery.
  Deletion protection is on in production.

## Observability

- Logs of the function are kept for 30 days (`log_retention_days`).
- X-Ray tracing is active on the function.
- Custom metrics use the namespace `orders/dev`. Metric filters count
  log lines of the function that contain `ERROR`, `Error` or `Exception`
  (`LoggedErrors`) and invocations that ran into the timeout (`Timeouts`). The
  function may publish its own metrics in the same namespace, either with
  `PutMetricData` or in embedded metric format. API Gateway publishes detailed metrics per route.
- Alarms notify the SNS topic `orders-dev-alarms`: function errors, function
  throttles, 5xx responses of the API (each: any in five minutes) and average
  API latency above `alarm_latency_threshold_ms` (default 2000) for fifteen
  minutes. Set `alarm_email` to subscribe an address; the recipient must
  confirm the subscription.

## Variables

All variables have defaults taken from the portal form. Override them in
`terraform.tfvars`.

| Variable | Default | Purpose |
| -------- | ------- | ------- |
| `project_name` | `orders` | First part of every resource name |
| `environment` | `dev` | `dev`, `staging` or `production` |
| `aws_region` | `eu-west-1` | Region of the resources |
| `function_runtime` | `nodejs24.x` | Lambda runtime |
| `function_handler` | `index.handler` | Entry point in the package |
| `function_architecture` | `x86_64` | `x86_64` or `arm64` |
| `memory_size` | `256` | Memory in MB |
| `timeout` | `30` | Timeout in seconds |
| `deployment_package` | none | Path to the zip file with the code |
| `deployment_package_s3` | none | Bucket, key and optional object version of the zip file |
| `function_environment` | `{}` | Additional environment variables |
| `log_retention_days` | `30` | Retention of the log groups |
| `cors_allowed_origins` | `["*"]` | Origins allowed by CORS |
| `throttle_rate_limit` | `1000` | Requests per second |
| `throttle_burst_limit` | `2000` | Burst size |
| `allow_self_sign_up` | `false` | Let users register themselves |
| `alarm_email` | none | Address notified by the alarms |
| `alarm_latency_threshold_ms` | `2000` | Latency that raises the alarm |
| `deployment_config_name` | `CodeDeployDefault.LambdaCanary10Percent5Minutes` | CodeDeploy deployment configuration |

## Outputs

| Output | Value |
| ------ | ----- |
| `api_endpoint` | URL that clients call |
| `api_id` | Identifier of the API |
| `api_origin_endpoint` | URL of the HTTP API behind CloudFront |
| `cloudfront_distribution_id` | CloudFront distribution |
| `web_acl_arn` | Web ACL |
| `cognito_user_pool_id`, `cognito_client_id`, `jwt_issuer` | User pool, app client and token issuer |
| `function_name`, `function_arn`, `function_version` | Function and its newest published version |
| `function_alias_arn` | Alias `live` |
| `function_role_arn` | Execution role |
| `function_log_group` | Log group of the function |
| `codedeploy_application`, `codedeploy_deployment_group` | CodeDeploy resources for traffic shifting |
| `table_name` | DynamoDB table |
| `metrics_namespace` | Namespace of the custom metrics |
| `alarm_topic_arn` | SNS topic of the alarms |

## Deployment

### State backend

The state is kept in S3. `versions.tf` declares an empty `backend "s3"` block;
bucket, key and region are given at init time:

```bash
terraform init \
  -backend-config="bucket=<state bucket>" \
  -backend-config="key=orders-serverless-api/terraform.tfstate" \
  -backend-config="region=<region of the bucket>" \
  -backend-config="use_lockfile=true"
terraform plan -out=tfplan
terraform apply tfplan
```

The bucket must exist already; enable versioning on it. `use_lockfile` makes
Terraform lock the state with an object next to it.

### Deploy workflow

`.github/workflows/deploy.yml` plans on pull requests and on pushes to `main`
and applies the plan on `main`, in the GitHub environment `production` (add
required reviewers to that environment to approve applies by hand). It signs in
to AWS with GitHub's OpenID Connect token; no access keys are stored.

| Name | Kind | Purpose |
| ---- | ---- | ------- |
| `AWS_ROLE_ARN` | secret or variable | Role the workflow assumes |
| `TF_STATE_BUCKET` | variable | S3 bucket of the Terraform state |
| `TF_STATE_REGION` | variable, optional | Region of that bucket if it is not `eu-west-1` |

Until `AWS_ROLE_ARN` and `TF_STATE_BUCKET` are set the workflow reports that
and skips plan and apply. The state key is
`<repository name>/terraform.tfstate`.

The role needs a trust policy for the identity provider
`token.actions.githubusercontent.com` with the audience `sts.amazonaws.com`
that allows the subjects `repo:example-org/orders-serverless-api:ref:refs/heads/main`,
`repo:example-org/orders-serverless-api:pull_request` and
`repo:example-org/orders-serverless-api:environment:production`.

### Required permissions

The identity that applies the configuration needs:

- on the state bucket: `s3:ListBucket`, and `s3:GetObject`, `s3:PutObject` and
  `s3:DeleteObject` on the state key and its `.tflock` object;
- to create, change and delete the resources of this configuration:
  Lambda, IAM roles and their inline policies (including `iam:PassRole` for
  them), CloudWatch Logs, API Gateway, Cognito user pools, WAF (in us-east-1), CloudFront, DynamoDB, CloudWatch metric filters and alarms, SNS, CodeDeploy;
- `s3:GetObject` on the package if `deployment_package_s3` is used.

### Traffic shifting

Terraform creates the alias `live` on the first apply and never moves it
afterwards. After an apply that published a new function version, CodeDeploy
moves the alias:

```bash
bash scripts/shift-traffic.sh
```

The script compares the version behind the alias with the output
`function_version` and, if they differ, starts a CodeDeploy deployment with
the configuration `deployment_config_name` and waits for it. It needs the AWS
CLI, `jq`, the initialised Terraform directory and permission for
`lambda:GetAlias`, `codedeploy:CreateDeployment`, `codedeploy:GetDeployment`,
`codedeploy:GetDeploymentConfig`, `codedeploy:GetApplicationRevision` and
`codedeploy:RegisterApplicationRevision`. The deploy workflow runs it after every apply.
A deployment is stopped and rolled back when the alarm
`orders-dev-function-errors` fires while traffic is being shifted.
Until the script has run, clients keep getting the previous version.

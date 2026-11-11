# orders serverless API

Infrastructure for a serverless API on Amazon Web Services, managed with Terraform.

## Selected options

| Option              | Value |
| ------------------- | ----- |
| Environment         | `dev` |
| Cloud provider      | `aws` |
| Region              | `eu-west-1` |
| Runtime             | `nodejs24` |
| Memory              | 256 MB |
| Timeout             | 30 s |
| API type            | `http` |
| CORS                | enabled |
| Throttling          | 1000 requests/s, burst 2000 |
| Authentication      | `jwt` |
| WAF                 | enabled |
| Database            | `nosql` |
| Cache               | disabled |
| Object storage      | disabled |
| Tracing             | enabled |
| Custom metrics      | enabled |
| Alarms              | enabled |
| Log retention       | 30 days |
| Deployment pipeline | included |
| Deployment strategy | `canary` |

What each option provisions, the inputs of the configuration and its outputs
are described in [Infrastructure](infrastructure.md).

## Pipeline

Every push and pull request runs the `CI` workflow:

1. `terraform fmt -check`, `terraform init -backend=false` and
   `terraform validate`
2. `terraform test`: a plan of the configuration against mocked providers
   (`tests/`)
3. TFLint with the rules in `.tflint.hcl`
4. A Trivy scan of the configuration that fails on high and critical findings
5. `mkdocs build --strict` of this documentation

None of these steps needs a cloud account.

The `Deploy` workflow plans on pull requests and applies on `main`. Until its
credentials are configured it reports that and skips plan and apply; see
[Infrastructure](infrastructure.md#deployment).

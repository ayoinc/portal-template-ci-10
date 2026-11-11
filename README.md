# orders serverless API

Terraform configuration for a serverless API on Amazon Web Services (Lambda behind API Gateway), environment `dev`.

The repository holds infrastructure only. The function code is built and
deployed from the application's own repository; see
[docs/infrastructure.md](docs/infrastructure.md) for how the function package
is supplied.

## Layout

| Path                       | Contents                                             |
| -------------------------- | ---------------------------------------------------- |
| `*.tf`                     | Terraform root configuration                         |
| `tests/`                   | Plan against mocked providers, run by `terraform test` |
| `.tflint.hcl`              | TFLint rules used by the pipeline                    |
| `docs/`                    | Documentation shown in the portal (TechDocs)         |
| `.github/workflows/ci.yml` | Validation that runs on every push and pull request  |
| `.github/workflows/deploy.yml` | Plan and apply, once cloud credentials are configured |
| `catalog-info.yaml`        | Registration of this repository in the portal        |

Any other directory belongs to the Terraform configuration and is described in
[docs/infrastructure.md](docs/infrastructure.md).

## Working locally

```bash
terraform init -backend=false
terraform fmt -check -recursive
terraform validate
tflint --init && tflint
```

## Pipeline

`ci.yml` needs no cloud account: it checks formatting, validates the
configuration, plans it against mocked providers, lints it with TFLint,
scans it with Trivy and builds the documentation.

`deploy.yml` plans on pull requests and applies on `main`. It skips both until
the credentials listed in [docs/infrastructure.md](docs/infrastructure.md) are
configured as repository secrets or variables.

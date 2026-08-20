# Adding a New Pipeline

This guide walks through everything needed to add a new ELT pipeline from scratch: the custom tap, Meltano config, Docker image, and Terraform infrastructure.

We use `tap-acme` as the example name throughout. Replace it with your actual tap name.

## Overview

A pipeline consists of four layers:

1. **Custom extractor** — Python Singer tap in `extractors/tap-acme/`
2. **Meltano config** — plugin declaration in `meltano/meltano.yml`
3. **Docker image** — one image per tap, built with `TAP_NAME` build arg
4. **Terraform** — Cloud Run Job + Secret Manager + Cloud Scheduler

## Step 1 — Create the custom extractor

Use the Meltano Singer SDK to scaffold a new tap:

```sh
cd extractors
uvx --from singer-sdk cookiecutter gh:meltano/sdk --directory=cookiecutter/tap-template
```

Answer the prompts (tap name: `tap-acme`, package name: `tap_acme`, etc.). This creates `extractors/tap-acme/` with the standard SDK structure.

### Extractor structure

```
extractors/tap-acme/
├── tap_acme/
│   ├── tap.py        # Main TapAcme class — authentication, stream list
│   ├── streams.py    # Stream classes — schema, replication, pagination
│   └── client.py     # Base REST client (auth headers, base URL)
├── tests/
│   └── test_core.py  # SDK standard test suite
├── pyproject.toml
└── uv.lock
```

### Key things to implement

**`tap.py`** — declare settings and streams:

```python
class TapAcme(Tap):
    name = "tap-acme"
    config_jsonschema = PropertiesList(
        Property("api_key", StringType, required=True, secret=True),
        Property("start_date", DateTimeType),
    ).to_dict()

    def discover_streams(self):
        return [AcmeOrders(self), AcmeProducts(self)]
```

**`streams.py`** — define each stream:

```python
class AcmeOrders(RESTStream):
    name = "orders"
    path = "/orders"
    primary_keys = ["id"]
    replication_key = "updated_at"
    schema = PropertiesList(
        Property("id", IntegerType, required=True),
        Property("updated_at", DateTimeType),
        Property("total", NumberType),
    ).to_dict()

    def get_url_params(self, context, next_page_token):
        params = {"limit": 100}
        if self.get_starting_replication_key_value(context):
            params["updated_after"] = self.get_starting_replication_key_value(context)
        if next_page_token:
            params["offset"] = next_page_token
        return params

    def get_next_page_token(self, response, previous_token):
        data = response.json()
        if len(data.get("results", [])) == 100:
            return (previous_token or 0) + 100
        return None
```

### Test the tap locally

```sh
cd extractors/tap-acme
uv sync
echo '{"api_key": "your-key"}' | uv run tap-acme --config - --discover  # catalog
echo '{"api_key": "your-key"}' | uv run tap-acme --config -              # full sync to stdout
uv run pytest
```

## Step 2 — Register in Meltano

Edit `meltano/meltano.yml` and add the extractor under `plugins.extractors`:

```yaml
plugins:
  extractors:
    # ... existing taps ...

    - name: tap-acme
      namespace: tap_acme
      pip_url: ${TAP_ACME_PATH}
      executable: tap-acme
      capabilities:
        - catalog
        - discover
        - state
      settings:
        - name: api_key
          kind: string
          sensitive: true
        - name: start_date
          kind: date_iso8601
```

Add the default path in the `env:` block at the bottom:

```yaml
env:
  TAP_TRAVEL_PERK_PATH: ../extractors/tap-travel-perk
  TAP_ACME_PATH: ../extractors/tap-acme          # add this
```

### Local development with editable install

Add this to `meltano/.env` (gitignored) so meltano picks up your code changes without reinstalling:

```sh
TAP_ACME_PATH=-e ../extractors/tap-acme
TAP_ACME__API_KEY=your-api-key
```

Note the double-underscore naming convention for settings: `TAP_{PLUGIN_NAMESPACE}__{SETTING_NAME}`.

Install the new plugin:

```sh
make meltano-install
# or specifically:
venv-meltano/bin/meltano --cwd meltano install extractor tap-acme
```

Test the pipeline locally:

```sh
make meltano-run TAP=tap-acme  # writes to meltano_dev BigQuery dataset
```

## Step 3 — Build the Docker image

The meltano Dockerfile is parameterized with `TAP_NAME` — no changes needed to the Dockerfile itself.

```sh
# Build dev image (includes both target-bigquery and target-bigquery-dev loaders)
make docker-build-meltano TAP=tap-acme

# Verify the image runs
docker run --rm \
  -e TAP_ACME__API_KEY="your-key" \
  europe-west1-docker.pkg.dev/lumapps-business-bi/bi/meltano-tap-acme:dev \
  meltano --environment=prod run tap-acme target-bigquery-dev

# Push to Artifact Registry
make docker-push-meltano TAP=tap-acme
```

## Step 4 — Create Terraform infrastructure

Create the pipeline folder structure:

```sh
mkdir -p infra/terraform/pipelines/tap-acme/dev
mkdir -p infra/terraform/pipelines/tap-acme/prod
```

### `dev/backend.tf`

```hcl
terraform {
  backend "gcs" {
    bucket = "lumapps-business-bi-terraform-state"
    prefix = "terraform/pipelines/tap-acme/dev"
  }
}
```

### `dev/providers.tf`

```hcl
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = "lumapps-business-bi"
  region  = "europe-west1"
}
```

### `dev/main.tf`

```hcl
locals {
  project_id  = "lumapps-business-bi"
  region      = "europe-west1"
  meltano_img = "${local.region}-docker.pkg.dev/${local.project_id}/bi/meltano-tap-acme"
}

data "google_service_account" "cloud_run_jobs" {
  account_id = "bi-cloud-run-jobs"
  project    = local.project_id
}

# ─── Secret ───────────────────────────────────────────────────────────────────

resource "google_secret_manager_secret" "api_key" {
  secret_id = "tap-acme-api-key"

  replication {
    user_managed {
      replicas { location = local.region }
    }
  }
}

resource "google_secret_manager_secret_iam_member" "api_key" {
  secret_id = google_secret_manager_secret.api_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = data.google_service_account.cloud_run_jobs.member
}

# ─── Dev Cloud Run Job ────────────────────────────────────────────────────────
# No schedule — trigger manually via:
#   gcloud run jobs execute meltano-tap-acme-dev --region europe-west1 --wait

module "dev" {
  source = "../../../modules/cloud-run-job"

  name       = "meltano-tap-acme-dev"
  project_id = local.project_id
  region     = local.region
  image      = "${local.meltano_img}:dev"
  command    = ["meltano"]
  args       = ["--environment=prod", "run", "tap-acme", "target-bigquery-dev"]

  service_account_email = data.google_service_account.cloud_run_jobs.email

  secret_env_vars = {
    TAP_ACME__API_KEY = google_secret_manager_secret.api_key.secret_id
  }
}
```

### `prod/backend.tf`

```hcl
terraform {
  backend "gcs" {
    bucket = "lumapps-business-bi-terraform-state"
    prefix = "terraform/pipelines/tap-acme/prod"
  }
}
```

### `prod/providers.tf`

Same as `dev/providers.tf`.

### `prod/main.tf`

```hcl
locals {
  project_id  = "lumapps-business-bi"
  region      = "europe-west1"
  meltano_img = "${local.region}-docker.pkg.dev/${local.project_id}/bi/meltano-tap-acme"
  schedule    = "0 1 * * *"  # 1am UTC daily — adjust to your needs
}

data "google_service_account" "cloud_run_jobs" {
  account_id = "bi-cloud-run-jobs"
  project    = local.project_id
}

data "google_service_account" "scheduler" {
  account_id = "bi-cloud-scheduler"
  project    = local.project_id
}

# Secret is owned by dev/ — read it here via data source
data "google_secret_manager_secret" "api_key" {
  secret_id = "tap-acme-api-key"
  project   = local.project_id
}

# ─── Prod Cloud Run Job + Scheduler ───────────────────────────────────────────

module "prod" {
  source = "../../../modules/cloud-run-job"

  name       = "meltano-tap-acme"
  project_id = local.project_id
  region     = local.region
  image      = "${local.meltano_img}:latest"
  command    = ["meltano"]
  args       = ["--environment=prod", "run", "tap-acme", "target-bigquery"]

  service_account_email           = data.google_service_account.cloud_run_jobs.email
  scheduler_service_account_email = data.google_service_account.scheduler.email
  schedule                        = local.schedule

  secret_env_vars = {
    TAP_ACME__API_KEY = data.google_secret_manager_secret.api_key.secret_id
  }
}
```

### Deploy dev environment

```sh
# Set the secret value BEFORE applying (Cloud Run requires at least one version)
make secret-set PIPELINE=tap-acme SECRET=api-key

# Init and apply
make tf-pipeline-init PIPELINE=tap-acme
make tf-pipeline-apply PIPELINE=tap-acme
```

`tf-pipeline-apply` automatically checks that all secrets have at least one version before running Terraform. If any secret is missing a value it will abort with a clear error.

### Deploy prod environment

Build and push the prod image first:

```sh
DOCKER_ENV=prod make docker-build-meltano TAP=tap-acme
DOCKER_ENV=prod make docker-push-meltano TAP=tap-acme

make tf-pipeline-init PIPELINE=tap-acme PIPELINE_ENV=prod
make tf-pipeline-apply PIPELINE=tap-acme PIPELINE_ENV=prod
```

## Step 5 — Run and verify

**Trigger the dev job manually:**

```sh
gcloud run jobs execute meltano-tap-acme-dev --region europe-west1 --wait
```

**Stream logs in real time:**

```sh
# In one terminal — start tailing
gcloud logging tail \
  'resource.type="cloud_run_job" AND resource.labels.job_name="meltano-tap-acme-dev"' \
  --project=lumapps-business-bi \
  --format="value(textPayload, jsonPayload.message)"

# In another terminal — trigger the job
gcloud run jobs execute meltano-tap-acme-dev --region europe-west1
```

**Verify data landed in BigQuery:**

Check the `meltano_dev` dataset in the BigQuery console for tables named after your streams.

## Cloud Run Job module reference

| Variable | Required | Default | Description |
|---|---|---|---|
| `name` | yes | — | Cloud Run Job name |
| `image` | yes | — | Docker image URI |
| `command` | no | `[]` | Entrypoint override |
| `args` | no | `[]` | Container arguments |
| `service_account_email` | yes | — | SA for job execution |
| `scheduler_service_account_email` | no | `""` | SA for Cloud Scheduler (required when `schedule` is set) |
| `schedule` | no | `""` | Cron in UTC — empty means manual-only |
| `env_vars` | no | `{}` | Plain environment variables |
| `secret_env_vars` | no | `{}` | `ENV_VAR` → Secret Manager secret ID |
| `cpu` | no | `"1"` | CPU allocation |
| `memory` | no | `"512Mi"` | Memory allocation |
| `timeout_seconds` | no | `3600` | Max task duration |
| `max_retries` | no | `0` | Retries on failure |

## Secret management

Secrets follow a two-layer model:

- **Terraform** creates the secret resource and IAM binding (what)
- **gcloud CLI** sets the secret value (what's in it)

This keeps actual credentials out of Terraform state and git history.

```sh
# Set a secret (prompts securely — value not stored in shell history)
make secret-set PIPELINE=tap-acme SECRET=api-key

# Rotate a secret (add a new version — Cloud Run always uses "latest")
echo -n "new-key" | gcloud secrets versions add tap-acme-api-key \
  --project=lumapps-business-bi --data-file=-

# List versions
gcloud secrets versions list tap-acme-api-key --project=lumapps-business-bi

# Disable an old version after rotating
gcloud secrets versions disable 1 --secret=tap-acme-api-key --project=lumapps-business-bi
```

## Checklist for a new pipeline

- [ ] Custom tap scaffolded and streams implemented
- [ ] Tap tested locally with `uv run tap-acme --config -`
- [ ] Unit tests pass: `uv run pytest` in `extractors/tap-acme/`
- [ ] Extractor added to `meltano/meltano.yml`
- [ ] Path env var added to `env:` block in `meltano.yml`
- [ ] Added `TAP_ACME_PATH=-e ../extractors/tap-acme` and credentials to `meltano/.env`
- [ ] Local pipeline run succeeds: `make meltano-run TAP=tap-acme`
- [ ] Dev Docker image builds: `make docker-build-meltano TAP=tap-acme`
- [ ] Dev Docker image pushed: `make docker-push-meltano TAP=tap-acme`
- [ ] Secret value set: `make secret-set PIPELINE=tap-acme SECRET=api-key`
- [ ] Dev Terraform applied: `make tf-pipeline-apply PIPELINE=tap-acme`
- [ ] Dev Cloud Run job executed and data verified in `meltano_dev`
- [ ] Prod image built and pushed: `DOCKER_ENV=prod make docker-build-meltano TAP=tap-acme`
- [ ] Prod Terraform applied: `make tf-pipeline-apply PIPELINE=tap-acme PIPELINE_ENV=prod`

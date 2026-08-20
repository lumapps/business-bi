# Deployment

This document covers how to build, deploy, and operate pipelines in GCP.

## Architecture overview

```
GitHub Actions
     │
     ├─ build Docker image
     ├─ push to Artifact Registry
     └─ update Cloud Run Job

Cloud Scheduler ──► Cloud Run Job ──► BigQuery
                        │
                   (pulls image from
                    Artifact Registry,
                    reads secrets from
                    Secret Manager)
```

All ELT pipelines run as **Cloud Run Jobs**: serverless batch containers that start on demand, run to completion, and stop. Cloud Scheduler triggers them on a cron schedule. There is no always-on infrastructure.

## GCP resources

| Resource | Name | Description |
|---|---|---|
| GCP project | `lumapps-business-bi` | Single project for all BI infra |
| Region | `europe-west1` | All resources |
| Artifact Registry | `europe-west1-docker.pkg.dev/lumapps-business-bi/bi` | Docker images |
| Terraform state | `gs://lumapps-business-bi-terraform-state` | Terraform remote state |
| Meltano state | `gs://lumapps-business-bi-meltano-state` | Incremental sync bookmarks |
| Service account (jobs) | `bi-cloud-run-jobs` | Executes Cloud Run Jobs |
| Service account (scheduler) | `bi-cloud-scheduler` | Triggers jobs via HTTP |

## Docker images

### Naming convention

| Tap | Dev image | Prod image |
|---|---|---|
| tap-travel-perk | `bi/meltano-tap-travel-perk:dev` | `bi/meltano-tap-travel-perk:latest` |
| dbt | `bi/dbt:dev` | `bi/dbt:latest` |

### Building images

```sh
# Meltano tap — dev (includes both target-bigquery and target-bigquery-dev)
make docker-build-meltano TAP=tap-travel-perk

# Meltano tap — prod (includes only target-bigquery)
DOCKER_ENV=prod make docker-build-meltano TAP=tap-travel-perk

# dbt
make docker-build-dbt                     # dev
DOCKER_ENV=prod make docker-build-dbt    # prod
```

### Pushing images

```sh
make docker-push-meltano TAP=tap-travel-perk              # push :dev
DOCKER_ENV=prod make docker-push-meltano TAP=tap-travel-perk  # push :latest

make docker-push-dbt               # push :dev
DOCKER_ENV=prod make docker-push-dbt  # push :latest
```

You must be authenticated first:

```sh
make docker-auth  # gcloud auth configure-docker europe-west1-docker.pkg.dev
```

## Terraform

### State isolation

Each pipeline has completely independent Terraform state files stored in GCS:

```
gs://lumapps-business-bi-terraform-state/
├── terraform/shared
├── terraform/pipelines/tap-travel-perk/dev
└── terraform/pipelines/tap-travel-perk/prod
```

Dev and prod are in separate state files — applying dev never affects prod resources, and vice versa.

### Shared infrastructure (one-time, already applied)

The `infra/terraform/shared/` module creates resources shared across all pipelines: GCP APIs, Artifact Registry, GCS buckets, service accounts, IAM roles.

```sh
make tf-shared-init
make tf-shared-plan
make tf-shared-apply
```

Only run this when adding new shared resources. It only needs to be done once per environment.

### Per-pipeline infrastructure

```sh
# Initialise (once per pipeline, and after any backend change)
make tf-pipeline-init PIPELINE=tap-travel-perk

# Preview changes
make tf-pipeline-plan PIPELINE=tap-travel-perk

# Apply (checks secrets first, then applies)
make tf-pipeline-apply PIPELINE=tap-travel-perk

# Prod
make tf-pipeline-init PIPELINE=tap-travel-perk PIPELINE_ENV=prod
make tf-pipeline-plan PIPELINE=tap-travel-perk PIPELINE_ENV=prod
make tf-pipeline-apply PIPELINE=tap-travel-perk PIPELINE_ENV=prod
```

`tf-pipeline-apply` runs `tf-pipeline-check-secrets` automatically before Terraform. If any secret for the pipeline has no versions, it aborts with an error telling you exactly which secret needs a value.

### Atlantis (production Terraform workflow)

For production changes, use Atlantis instead of running `terraform apply` locally:

1. Open a PR with your Terraform changes
2. Atlantis posts a `terraform plan` comment automatically
3. Review the plan in the PR
4. Comment `atlantis apply` to apply

Only use `make tf-pipeline-apply` locally for the dev environment.

## Secret management

### First-time setup (new pipeline)

Secrets must have at least one version before Cloud Run can reference them. Always set the secret value before the first `terraform apply` that creates the Cloud Run Job.

```sh
make secret-set PIPELINE=tap-travel-perk SECRET=api-key
```

This prompts for the value interactively — the value is not stored in shell history.

### Rotating a secret

Cloud Run always references `latest`. Add a new version and the next job execution picks it up automatically — no redeployment needed.

```sh
echo -n "new-api-key" | gcloud secrets versions add tap-travel-perk-api-key \
  --project=lumapps-business-bi --data-file=-
```

After confirming the new version works, disable the old one:

```sh
gcloud secrets versions disable VERSION_NUMBER \
  --secret=tap-travel-perk-api-key \
  --project=lumapps-business-bi
```

### Viewing secret metadata (not value)

```sh
gcloud secrets versions list tap-travel-perk-api-key --project=lumapps-business-bi
```

## Running jobs

### Manual trigger (dev or prod)

```sh
# Dev job
gcloud run jobs execute meltano-tap-travel-perk-dev \
  --region europe-west1 \
  --wait

# Prod job (manual trigger outside of schedule)
gcloud run jobs execute meltano-tap-travel-perk \
  --region europe-west1 \
  --wait
```

### Scheduled trigger (prod)

Prod jobs run automatically on the schedule defined in `prod/main.tf` (`schedule` variable). Cloud Scheduler sends an HTTP POST to the Cloud Run Jobs API.

View upcoming scheduled executions in the GCP Console: **Cloud Scheduler → bi-meltano-tap-travel-perk**.

### Monitor logs

```sh
# Stream live
gcloud logging tail \
  'resource.type="cloud_run_job" AND resource.labels.job_name="meltano-tap-travel-perk-dev"' \
  --project=lumapps-business-bi \
  --format="value(textPayload, jsonPayload.message)"

# Historical
gcloud logging read \
  'resource.type="cloud_run_job" AND resource.labels.job_name="meltano-tap-travel-perk-dev"' \
  --project=lumapps-business-bi \
  --limit=100 \
  --order=asc \
  --format="value(textPayload, jsonPayload.message)"
```

## Authentication — Workload Identity Federation

GitHub Actions authenticates to GCP via OIDC (no JSON service account key files). The workflow needs:

```yaml
permissions:
  id-token: write   # needed to get an OIDC token
  contents: read
```

And the auth step:

```yaml
- uses: google-github-actions/auth@v2
  with:
    workload_identity_provider: ${{ secrets.WIF_PROVIDER }}
    service_account: ${{ secrets.GCP_SA_EMAIL }}
```

The WIF provider and service account are configured once in the shared Terraform module.

## Deployment checklist

For deploying a new version of an existing pipeline:

1. [ ] Make changes to the tap or meltano config
2. [ ] Test locally: `make meltano-run TAP=tap-travel-perk`
3. [ ] Build dev image: `make docker-build-meltano TAP=tap-travel-perk`
4. [ ] Test the Docker image locally
5. [ ] Push dev image: `make docker-push-meltano TAP=tap-travel-perk`
6. [ ] Trigger dev Cloud Run job and verify in BigQuery
7. [ ] Build prod image: `DOCKER_ENV=prod make docker-build-meltano TAP=tap-travel-perk`
8. [ ] Push prod image: `DOCKER_ENV=prod make docker-push-meltano TAP=tap-travel-perk`
9. [ ] Cloud Run picks up the new image on the next scheduled execution (or trigger manually)

For infrastructure changes, use Atlantis (prod) or `make tf-pipeline-apply` (dev).

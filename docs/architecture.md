# Architecture

## Overview

`business-bi` is a monorepo for all business intelligence infrastructure at Lumapps. It owns:

- **ELT pipelines** (Meltano + custom Singer taps) — extract data from third-party APIs and load it into BigQuery
- **Data transformations** (dbt) — clean, join, and model raw data into analytics-ready tables
- **Custom extractors** (Singer taps) — in-repo Python packages for each data source
- **GCP infrastructure** (Terraform) — Cloud Run Jobs, Cloud Scheduler, Secret Manager, Artifact Registry

Everything runs on GCP. There are no always-on servers. Each pipeline is a Docker container that starts, runs, and stops.

## Data flow

```
Third-party API
      │
      ▼
tap-xxx (Singer extractor)
      │  Singer protocol (SCHEMA, RECORD, STATE messages)
      ▼
target-bigquery (Singer loader)
      │
      ▼
BigQuery: meltano dataset (raw)
      │
      ▼
dbt: bronze → silver → gold
      │
      ▼
BigQuery: analytics-ready tables
```

### Layer definitions

| Layer | BigQuery dataset | Description |
|---|---|---|
| Raw | `meltano` / `meltano_dev` | Unmodified data as loaded by meltano |
| Bronze | `bronze` / `bronze_dev` | Source data with light casting and deduplication |
| Silver | `silver` / `silver_dev` | Joined, cleaned, business-logic applied |
| Gold | `gold` / `gold_dev` | Aggregated, metric tables ready for dashboards |

## GCP infrastructure

```
Artifact Registry (Docker images)
         │
         ▼
Cloud Run Job ◄── Cloud Scheduler (cron)
         │
         ├─ reads secrets from Secret Manager
         ├─ reads state from GCS (meltano incremental)
         └─ writes data to BigQuery
```

### Why Cloud Run Jobs?

- **Serverless** — no infrastructure to manage, scales to zero when not running
- **Pay per use** — billed only for actual execution time
- **Simple deployment** — update the image URI via `gcloud run jobs update`
- **Isolated** — each tap is its own container with its own dependencies

### Service accounts and IAM

Two service accounts are used:

| Service account | Role | Used by |
|---|---|---|
| `bi-cloud-run-jobs` | BigQuery Editor, Artifact Registry Reader, Storage Object Admin | Cloud Run Job containers |
| `bi-cloud-scheduler` | Cloud Run Invoker | Cloud Scheduler HTTP triggers |

### Secret Manager model

Secrets follow a two-layer model to keep credentials out of Terraform state and git:

1. **Terraform** creates the secret resource + IAM binding (grants the Cloud Run SA read access)
2. **gcloud CLI** sets the actual secret value (`make secret-set`)

Cloud Run Jobs always reference `secret/latest`. Rotating a secret just means adding a new version — no redeployment needed.

## Python environments

Two completely separate Python environments are required because meltano and dbt have conflicting transitive dependencies:

| Environment | Python | Venv | Lockfile |
|---|---|---|---|
| dbt + dev tools | 3.13 | `venv/` | `requirements/main.txt` |
| Meltano | 3.10 | `venv-meltano/` | `requirements/meltano.txt` |

Meltano uses Python 3.10 specifically because `z3-target-bigquery` (the BigQuery loader used in production) depends on `pendulum 2.x`, which has pre-built wheels only for Python ≤ 3.11. Python 3.10 matches the production Docker image.

## Dependency management

The project uses a pip-tools pattern via `uv`:

```
requirements/dbt.in        →  requirements/dbt.txt
requirements/meltano.in    →  requirements/meltano.txt
requirements/main.in       →  requirements/main.txt
     (includes dbt.txt + dev tools)
```

- `.in` files — human-maintained, direct dependencies only
- `.txt` files — fully pinned lockfiles with SHA-256 hashes, committed to git, never edited by hand

Lockfiles are compiled for `linux/amd64` (the Docker and CI platform) even when developing on macOS.

## Custom extractors (Singer taps)

Custom taps live in `extractors/tap-xxx/` as standalone Python packages. This design allows:

- **Atomic commits** — tap code and pipeline config change together in one PR
- **Independent testing** — each tap has its own `pyproject.toml`, test suite, and lockfile
- **Flexible installation** — the `pip_url` is controlled by an env var, so local dev uses an editable install (`-e ../extractors/tap-xxx`) while Docker uses the repository path

```yaml
# meltano/meltano.yml
plugins:
  extractors:
    - name: tap-travel-perk
      pip_url: ${TAP_TRAVEL_PERK_PATH}

env:
  TAP_TRAVEL_PERK_PATH: ../extractors/tap-travel-perk  # default: install from path

# meltano/.env (gitignored, local override)
TAP_TRAVEL_PERK_PATH=-e ../extractors/tap-travel-perk  # editable: picks up code changes instantly
```

## Docker image strategy

One Docker image per tap, parameterized by `TAP_NAME` build arg:

```
bi/meltano-tap-travel-perk:dev     # dev image — includes target-bigquery-dev loader
bi/meltano-tap-travel-perk:latest  # prod image — includes only target-bigquery loader
bi/dbt:dev
bi/dbt:latest
```

A single parameterized Dockerfile handles all taps. The Dockerfile:

1. (Builder stage) Pre-builds all meltano Python wheels using `pip wheel`
2. (Runtime stage) Installs wheels, runs `meltano install extractor $TAP_NAME && meltano install loader $LOADERS`
3. Sets `WORKDIR` to `/app/meltano` so `meltano run` finds `meltano.yml`
4. Transfers ownership of `/app/meltano` to UID 1000 before switching to non-root user

## Terraform layout

```
infra/terraform/
├── shared/                          # Shared GCP resources (one state)
│   ├── main.tf                      # APIs, Artifact Registry, GCS, IAM, SAs
│   ├── backend.tf
│   └── providers.tf
├── modules/
│   └── cloud-run-job/               # Reusable module
│       ├── main.tf                  # Cloud Run Job + optional Cloud Scheduler
│       ├── variables.tf
│       └── outputs.tf
└── pipelines/
    └── tap-travel-perk/
        ├── dev/                     # Separate state from prod
        │   ├── main.tf              # Secret resource + dev Cloud Run Job
        │   ├── backend.tf
        │   └── providers.tf
        └── prod/                    # Separate state from dev
            ├── main.tf              # Prod Cloud Run Job + Cloud Scheduler
            ├── backend.tf
            └── providers.tf
```

### Why separate dev and prod state files?

If dev and prod shared one Terraform state, `terraform apply` for dev would also plan changes for prod resources — and could destroy them if the prod configuration wasn't present locally. With separate state files, dev and prod are completely independent: applying dev has zero effect on prod.

The secret resource is owned by the `dev/` state because it must exist before prod can reference it. Prod reads it via `data "google_secret_manager_secret"` (a read-only lookup, not management).

## Meltano state (incremental sync)

Meltano tracks the last sync bookmark (e.g. `updated_at` timestamp) in GCS so that each run only fetches new records. The state bucket is `lumapps-business-bi-meltano-state`.

State is stored per pipeline:

```
gs://lumapps-business-bi-meltano-state/
└── tap-travel-perk/
    └── state.json
```

To reset to a full sync: `meltano state clear tap-travel-perk` (locally) or delete the GCS object.

## CI/CD

GitHub Actions workflows handle:
- Building and pushing Docker images on merge to `main`
- Running `dbt test` in CI
- Applying Terraform via Atlantis on PRs

Path filters prevent unnecessary builds — a change to `meltano/` doesn't trigger the dbt workflow and vice versa.

Authentication to GCP uses **Workload Identity Federation** (WIF): GitHub Actions gets an OIDC token, which GCP exchanges for short-lived credentials. No JSON service account key files are stored in GitHub secrets.

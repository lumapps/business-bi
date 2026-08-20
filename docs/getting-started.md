# Getting Started

This guide walks a new contributor through setting up a local development environment from scratch.

## Prerequisites

You need the following tools installed on your machine before anything else:

- **mise** — manages tool versions (Python, gcloud, Terraform). [Install](https://mise.jdx.dev/getting-started.html)
- **Docker** — for building and testing images locally
- **git**

## 1. Clone and install tools

```sh
git clone git@github.com:lumapps/business-bi.git
cd business-bi
mise install
```

`mise install` reads `mise.toml` and installs the exact versions of Python (3.13 and 3.10), gcloud, and Terraform used by the project. Always run this first when you pull changes that modify `mise.toml`.

## 2. Authenticate to GCP

```sh
gcloud auth login
gcloud auth application-default login
gcloud config set project lumapps-business-bi
```

The first command gives you access to gcloud CLI commands. The second sets up Application Default Credentials (ADC), which dbt and other tools use to authenticate to BigQuery without a service account key file.

## 3. Set up the dbt environment

```sh
make init
```

This creates `venv/` with Python 3.13, installs all dbt dependencies from `requirements/main.txt`, and runs `dbt deps` to install dbt packages.

Verify it works:

```sh
venv/bin/dbt debug --project-dir dbt --profiles-dir dbt
```

You should see "All checks passed."

## 4. Set up the Meltano environment

Meltano has conflicting dependencies with dbt and lives in a separate venv.

```sh
make init-meltano
```

This creates `venv-meltano/` with Python 3.10 and installs meltano from `requirements/meltano.txt`.

Then create your local credentials file:

```sh
cp meltano/.env.example meltano/.env
```

Edit `meltano/.env` and fill in the API keys for the taps you want to work with. These values are never committed to git.

For tap-travel-perk the required variable is:

```sh
TAP_TRAVEL_PERK__API_KEY=your-api-key-here
```

Install meltano plugins:

```sh
make meltano-install
```

## 5. Authenticate Docker to Artifact Registry

Run this once to allow Docker to push/pull from the company registry:

```sh
make docker-auth
```

## Repository structure

```
business-bi/
├── dbt/                          # dbt project — data transformations
│   ├── models/                   # SQL models (bronze / silver / gold layers)
│   ├── macros/
│   ├── dbt_project.yml
│   └── profiles.yml
├── meltano/                      # Meltano project — ELT orchestration
│   ├── meltano.yml               # Plugin definitions and pipeline config
│   ├── logging-dev.yaml          # Colored console logging for local dev
│   └── logging-prod.yaml         # JSON stderr logging for Cloud Run
├── extractors/                   # Custom Singer taps as Python packages
│   └── tap-travel-perk/
│       ├── src/tap_travel_perk/
│       └── pyproject.toml
├── requirements/                 # Dependency lockfiles (never edit .txt by hand)
│   ├── dbt.in / dbt.txt
│   ├── meltano.in / meltano.txt
│   └── main.in / main.txt
├── infra/
│   ├── terraform/                # GCP infrastructure as code
│   │   ├── shared/               # Shared resources (APIs, IAM, Artifact Registry)
│   │   ├── modules/cloud-run-job/
│   │   └── pipelines/tap-travel-perk/dev|prod/
│   └── docker/
│       ├── dbt.Dockerfile
│       └── meltano.Dockerfile
├── Makefile                      # Local dev shortcuts — start here
└── mise.toml                     # Pinned tool versions
```

## Key concepts

### Two separate Python environments

| Environment | Python | Venv | Purpose |
|---|---|---|---|
| dbt + dev tools | 3.13 | `venv/` | SQL transformations, linting |
| Meltano | 3.10 | `venv-meltano/` | ELT pipelines, Singer taps |

They cannot share a venv because some dependencies conflict. The `MELTANO` variable in the Makefile points to `venv-meltano/bin/meltano`.

### Dev vs prod isolation

All dev work writes to `_dev`-suffixed BigQuery datasets (`meltano_dev`, `bronze_dev`, etc.) in the same GCP project. You never touch production datasets locally.

| Component | Dev | Prod |
|---|---|---|
| dbt | `--target dev` → `*_dev` datasets | `--target prod` |
| Meltano | `target-bigquery-dev` → `meltano_dev` | `target-bigquery` → `meltano` |
| Docker image tag | `:dev` | `:latest` |
| Cloud Run job | `*-dev` (no schedule) | `*` (Cloud Scheduler) |

### Dependency management

Dependencies follow a pip-tools pattern using `uv`:

- `.in` files — human-maintained, direct dependencies only
- `.txt` files — generated lockfiles with all transitive deps and SHA-256 hashes, committed to git

Never edit `.txt` files by hand. After changing a `.in` file, recompile with:

```sh
make upgrade-requirements
```

Then sync your venv:

```sh
make sync-venv         # dbt venv
make sync-venv-meltano # meltano venv
```

## Makefile reference

```sh
make help              # print all available targets with descriptions

# Setup
make init              # dbt venv + deps (run after cloning)
make init-meltano      # meltano venv + plugins

# dbt
make dbt-run           # dbt run --target dev
make dbt-test          # dbt test --target dev
DBT_TARGET=prod make dbt-run  # run against prod

# Meltano
make meltano-run TAP=tap-travel-perk          # dev pipeline
MELTANO_ENV=prod make meltano-run TAP=tap-travel-perk  # prod pipeline

# Docker
make docker-build-meltano TAP=tap-travel-perk # build :dev image
make docker-push-meltano TAP=tap-travel-perk  # push :dev image
DOCKER_ENV=prod make docker-build-meltano TAP=tap-travel-perk  # build :latest

# Terraform
make tf-pipeline-apply PIPELINE=tap-travel-perk             # dev
make tf-pipeline-apply PIPELINE=tap-travel-perk PIPELINE_ENV=prod  # prod

# Secrets
make secret-set PIPELINE=tap-travel-perk SECRET=api-key     # prompts for value
```

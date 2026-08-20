# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

`business-bi` is a monorepo for business intelligence infrastructure: ELT pipelines (Meltano), data transformations (dbt), custom Singer taps, and GCP infrastructure (Terraform). Everything runs on GCP as Cloud Run Jobs triggered by Cloud Scheduler, writing to BigQuery.

## Repository Structure

```
business-bi/
├── dbt/                          # dbt project targeting BigQuery
├── meltano/                      # Meltano project (ELT orchestration)
│   ├── meltano.yml
│   └── .env.example
├── extractors/tap-xxx/           # custom Singer taps as Python packages (in-repo)
│   ├── src/
│   └── pyproject.toml
├── requirements/                 # pip-tools/uv lockfiles (see Dependency Management)
│   ├── dbt.in / dbt.txt
│   ├── meltano.in / meltano.txt
│   └── main.in / main.txt
├── infra/
│   ├── terraform/                # GCP infra: Cloud Run Jobs, Scheduler, WIF, IAM
│   │   └── modules/cloud-run-job/
│   └── docker/                   # dbt.Dockerfile, meltano.Dockerfile
├── Makefile
└── atlantis.yaml                 # Atlantis config for Terraform PRs
```

## Local Tooling

Tool versions are pinned in `mise.toml`. Run `mise install` before anything else to get the correct Python (3.13), gcloud, and Terraform versions.

## Key Commands

**dbt** (run from `dbt/`):
```sh
dbt run --target dev      # local iteration — writes to *_dev BigQuery datasets
dbt run --target prod     # production run (CI/Cloud Run)
dbt test
dbt docs generate && dbt docs serve
```

**Meltano** (run from `meltano/`):
```sh
meltano install                                        # install all plugins
meltano --environment=dev run tap-xxx target-bigquery
meltano --environment=prod run tap-xxx target-bigquery
```

**Terraform** (run from `infra/terraform/`):
```sh
terraform init
terraform plan
terraform apply   # only locally before Atlantis is set up; use `atlantis apply` after
```

**Dependencies:**
```sh
# Install local dev environment (dbt + dev tools):
uv pip sync requirements/main.txt

# Install meltano venv (separate — conflicts with dbt deps):
uv pip sync requirements/meltano.txt

# Recompile a lockfile after editing a .in file:
uv pip compile --generate-hashes --strip-extras --python-platform=linux requirements/<file>.in --output-file requirements/<file>.txt
```

## Architecture & Key Decisions

### GCP Deployment
- Each ELT pipeline and dbt run is its own **Cloud Run Job** (serverless, pay-per-use, scale to zero)
- **Cloud Scheduler** triggers jobs via HTTP
- Docker images stored in the company's internal container registry
- Secrets stored in **GCP Secret Manager**, injected as env vars in Cloud Run

### Authentication
- **Workload Identity Federation (WIF)** — no JSON service account keys. GitHub Actions authenticate to GCP via OIDC tokens (`id-token: write` permission required).

### dbt Targets & Dev Isolation
- `dev` target writes to `*_dev` BigQuery datasets (e.g. `analytics_dev`) — safe for local iteration
- `prod` target writes to production datasets
- Active target controlled by `DBT_TARGET` env var (defaults to `dev` locally, `prod` in CI)

### Two Separate Python Venvs
Meltano and dbt have conflicting Python dependencies and cannot share a venv (both run Python 3.13):
- `venv/` — dbt + dev tools, installed from `requirements/main.txt`
- `venv-meltano/` — meltano only, installed from `requirements/meltano.txt`

### Dependency Management (pip-tools / uv pattern)
- `.in` files: human-maintained, list only direct dependencies
- `.txt` files: generated lockfiles with all transitive deps + SHA-256 hashes — never edited by hand
- `dbt.in` → minimal deps for the production dbt Docker image
- `meltano.in` → meltano venv deps
- `main.in` → local dev environment; includes `dbt.txt` via `-r dbt.txt` then adds dev tools on top
- To add/upgrade a dep: edit the `.in` file → recompile the `.txt` → run `uv pip sync` → commit both

### Custom Extractor Installation (in-repo taps)
Custom taps live in `extractors/tap-xxx/` inside this monorepo. Meltano resolves them via an env var so the source can differ between local dev and production without changing `meltano.yml`.

```yaml
# meltano/meltano.yml
plugins:
  extractors:
    - name: tap-xxx
      pip_url: ${TAP_XXX_PATH}

env:
  TAP_XXX_PATH: ../extractors/tap-xxx   # default: install from repo path
```

```bash
# meltano/.env  (gitignored)
# Override for fast local iteration — picks up code changes without reinstalling:
TAP_XXX_PATH="-e ../extractors/tap-xxx"
```

In Docker, `extractors/` is copied into the image before `meltano install` so the default path resolves inside the container.

### Terraform Workflow (Atlantis)
- Atlantis runs on Cloud Run; posts `terraform plan` as a PR comment, applies on `atlantis apply` comment
- Config in `atlantis.yaml` at root, scoped to `infra/terraform/`
- Do not run `terraform apply` locally once Atlantis is live

### CI/CD (GitHub Actions)
- Path filters prevent unnecessary rebuilds: `paths: ['dbt/**']`, `paths: ['meltano/**']`, etc.
- Deploy workflows build & push Docker images, then update Cloud Run Jobs via `gcloud run jobs update`

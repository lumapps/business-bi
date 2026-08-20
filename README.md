# business-bi

Business intelligence infrastructure for Lumapps: ELT pipelines, data transformations, and GCP infrastructure — all in one monorepo.

## What this repo does

- **Extracts** data from third-party APIs (TravelPerk, Lucca, ...) using custom Singer taps
- **Loads** raw data into BigQuery via Meltano
- **Transforms** raw data into analytics-ready tables using dbt (bronze → silver → gold)
- **Runs** everything as Cloud Run Jobs on a cron schedule, with zero always-on infrastructure

## Documentation

| | |
|---|---|
| [Getting Started](docs/getting-started.md) | Set up your local environment, understand the project layout |
| [Adding a Pipeline](docs/adding-a-pipeline.md) | Add a new tap, Meltano config, Docker image, and Terraform infra |
| [Testing](docs/testing.md) | Test taps, pipelines, and dbt models locally and on dev GCP |
| [Deployment](docs/deployment.md) | Build and push images, manage secrets, run and monitor jobs |
| [Architecture](docs/architecture.md) | How the pieces fit together, design decisions, data flow |

## Quick reference

```sh
mise install               # install pinned tool versions (Python, gcloud, Terraform)
make init                  # set up dbt venv
make init-meltano          # set up meltano venv

make dbt-run               # dbt run --target dev
make meltano-run TAP=tap-travel-perk  # ELT pipeline → meltano_dev

make docker-build-meltano TAP=tap-travel-perk  # build :dev image
make docker-push-meltano TAP=tap-travel-perk   # push to Artifact Registry

make tf-pipeline-apply PIPELINE=tap-travel-perk  # deploy dev Cloud Run job
make secret-set PIPELINE=tap-travel-perk SECRET=api-key  # set a secret value

make help                  # all available targets
```

## Stack

| Component | Technology |
|---|---|
| ELT orchestration | [Meltano](https://meltano.com) |
| Singer extractors | [Singer SDK](https://sdk.meltano.com) (Python) |
| Data transformation | [dbt](https://www.getdbt.com) |
| Data warehouse | Google BigQuery |
| Container runtime | Cloud Run Jobs |
| Scheduling | Cloud Scheduler |
| Secrets | GCP Secret Manager |
| Docker registry | GCP Artifact Registry |
| Infrastructure | Terraform |
| Dependency management | pip-tools + uv |
| Python version management | mise |

# Testing

This document covers how to test each component of the project locally and on the dev environment in GCP.

## Custom taps (Singer extractors)

Each tap in `extractors/tap-xxx/` is a standalone Python package with its own test suite.

### Unit tests

```sh
cd extractors/tap-travel-perk
uv sync
uv run pytest
```

The Meltano Singer SDK provides a standard test suite via `singer_sdk.testing` that validates the tap's catalog and schema output. Tests live in `tests/`.

### Manual end-to-end test (stdout)

Run the tap against the real API and inspect the output:

```sh
cd extractors/tap-travel-perk

# Discover catalog (list all streams and their schemas)
echo '{"api_key": "your-key"}' | uv run tap-travel-perk --config - --discover | jq .

# Full sync — outputs Singer messages (SCHEMA, RECORD, STATE) to stdout
echo '{"api_key": "your-key", "start_date": "2024-01-01"}' \
  | uv run tap-travel-perk --config -

# Incremental sync — pass a state file
echo '{"api_key": "your-key"}' \
  | uv run tap-travel-perk --config - --state state.json
```

### Type checking

```sh
cd extractors/tap-travel-perk
uv run mypy tap_travel_perk
```

---

## Meltano pipelines

### Local run (writes to dev BigQuery datasets)

```sh
make meltano-run TAP=tap-travel-perk
```

This runs `meltano --environment=dev run tap-travel-perk target-bigquery-dev`, which writes to the `meltano_dev` dataset in BigQuery.

The first run does a full sync. Subsequent runs are incremental — meltano tracks state in the GCS bucket `lumapps-business-bi-meltano-state`.

### Local run against target-jsonl (no BigQuery needed)

If you want to test extraction without writing to BigQuery:

```sh
venv-meltano/bin/meltano --cwd meltano \
  --environment=dev \
  run tap-travel-perk target-jsonl
```

Output lands in `meltano/output/` as JSONL files.

### Debug a single stream

```sh
venv-meltano/bin/meltano --cwd meltano \
  --environment=dev \
  run tap-travel-perk target-jsonl \
  --select "tap-travel-perk.bookings"
```

### Reset state (full re-sync)

```sh
venv-meltano/bin/meltano --cwd meltano state clear tap-travel-perk
```

### Inspect state

```sh
venv-meltano/bin/meltano --cwd meltano state get tap-travel-perk
```

### Check installed plugins

```sh
venv-meltano/bin/meltano --cwd meltano inspect
```

---

## dbt transformations

### Local run (writes to `*_dev` datasets)

```sh
make dbt-run     # dbt run --target dev
make dbt-test    # dbt test --target dev
```

The `dev` target writes to `bronze_dev`, `silver_dev`, `gold_dev` BigQuery datasets.

### Run a single model

```sh
venv/bin/dbt run --project-dir dbt --profiles-dir dbt \
  --target dev \
  --select my_model_name
```

### Run a model and all its dependencies

```sh
venv/bin/dbt run --project-dir dbt --profiles-dir dbt \
  --target dev \
  --select +my_model_name
```

### Run only models in a specific layer

```sh
venv/bin/dbt run --project-dir dbt --profiles-dir dbt \
  --target dev \
  --select tag:layer:bronze
```

### Compile SQL without running

```sh
venv/bin/dbt compile --project-dir dbt --profiles-dir dbt --target dev
```

Compiled SQL appears in `dbt/target/compiled/`.

### Browse docs locally

```sh
venv/bin/dbt docs generate --project-dir dbt --profiles-dir dbt
venv/bin/dbt docs serve --project-dir dbt --profiles-dir dbt
```

Opens a browser at `http://localhost:8080` with the full lineage graph and column descriptions.

### Check connection

```sh
venv/bin/dbt debug --project-dir dbt --profiles-dir dbt
```

If the connection fails, check that `gcloud auth application-default login` has been run and that your account has BigQuery access.

---

## Docker images

### Build and test locally before pushing

```sh
# Build the dev image
make docker-build-meltano TAP=tap-travel-perk

# Run a quick check — prints the meltano version and help
docker run --rm \
  europe-west1-docker.pkg.dev/lumapps-business-bi/bi/meltano-tap-travel-perk:dev \
  meltano --version

# Full pipeline run inside the container, writing to BigQuery dev dataset
docker run --rm \
  -e TAP_TRAVEL_PERK__API_KEY="your-api-key" \
  europe-west1-docker.pkg.dev/lumapps-business-bi/bi/meltano-tap-travel-perk:dev \
  meltano --environment=prod run tap-travel-perk target-bigquery-dev
```

Note: the container uses `--environment=prod` — the `meltano.yml` env controls which target is available, not which BigQuery dataset is used. The `target-bigquery-dev` loader always writes to `meltano_dev`.

---

## Dev Cloud Run jobs on GCP

The dev Cloud Run jobs (`*-dev`) have no schedule and must be triggered manually.

### Trigger and wait for completion

```sh
gcloud run jobs execute meltano-tap-travel-perk-dev \
  --region europe-west1 \
  --wait
```

### Stream logs in real time

Open two terminals:

```sh
# Terminal 1 — tail logs
gcloud logging tail \
  'resource.type="cloud_run_job" AND resource.labels.job_name="meltano-tap-travel-perk-dev"' \
  --project=lumapps-business-bi \
  --format="value(textPayload, jsonPayload.message)"

# Terminal 2 — trigger the job
gcloud run jobs execute meltano-tap-travel-perk-dev --region europe-west1
```

### View past executions

```sh
gcloud run jobs executions list \
  --job=meltano-tap-travel-perk-dev \
  --region=europe-west1 \
  --project=lumapps-business-bi
```

### Get logs from a specific execution

```sh
gcloud logging read \
  'resource.type="cloud_run_job" AND resource.labels.job_name="meltano-tap-travel-perk-dev"' \
  --project=lumapps-business-bi \
  --limit=100 \
  --format="value(textPayload, jsonPayload.message)" \
  --order=asc
```

---

## Linting and pre-commit

### SQL linting (dbt models)

```sh
venv/bin/sqlfluff lint dbt/models/
venv/bin/sqlfluff fix dbt/models/    # auto-fix
```

### Python linting (custom taps)

```sh
cd extractors/tap-travel-perk
uv run ruff check .
uv run ruff format .
```

### Pre-commit hooks

Pre-commit runs on every `git commit` inside `extractors/tap-travel-perk/`:

```sh
cd extractors/tap-travel-perk
pre-commit install          # install hooks (once)
pre-commit run --all-files  # run manually
```

Hooks include: ruff (lint + format), JSON/YAML/TOML validation, typo detection, uv lock file audit.

---

## BigQuery dataset reference

| Dataset | Target | Description |
|---|---|---|
| `meltano` | prod | Raw data from meltano extractors |
| `meltano_dev` | dev | Raw data from local/dev runs |
| `bronze` | prod | Lightly cleaned source data |
| `bronze_dev` | dev | |
| `silver` | prod | Joined and deduplicated |
| `silver_dev` | dev | |
| `gold` | prod | Business-ready metrics |
| `gold_dev` | dev | |

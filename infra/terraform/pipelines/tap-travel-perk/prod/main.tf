locals {
  project_id  = "lumapps-business-bi"
  region      = "europe-west1"
  meltano_img = "${local.region}-docker.pkg.dev/${local.project_id}/bi/meltano-tap-travel-perk"

  # midnight UTC — full table refresh, matches dataplatform schedule
  schedule = "0 0 * * *"
}

# ─── Look up shared resources ─────────────────────────────────────────────────

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
  secret_id = "tap-travel-perk-api-key"
  project   = local.project_id
}

# ─── Prod Cloud Run Job + Scheduler ───────────────────────────────────────────

module "prod" {
  source = "../../../modules/cloud-run-job"

  name       = "meltano-tap-travel-perk"
  project_id = local.project_id
  region     = local.region
  image      = "${local.meltano_img}:latest"
  command    = ["meltano"]
  args       = ["--environment=prod", "run", "tap-travel-perk", "target-bigquery"]

  service_account_email           = data.google_service_account.cloud_run_jobs.email
  scheduler_service_account_email = data.google_service_account.scheduler.email
  schedule                        = local.schedule

  secret_env_vars = {
    TAP_TRAVEL_PERK__API_KEY = data.google_secret_manager_secret.api_key.secret_id
  }
}

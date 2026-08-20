locals {
  project_id  = "lumapps-business-bi"
  region      = "europe-west1"
  meltano_img = "${local.region}-docker.pkg.dev/${local.project_id}/bi/meltano-tap-travel-perk"
}

# ─── Look up shared resources ─────────────────────────────────────────────────

data "google_service_account" "cloud_run_jobs" {
  account_id = "bi-cloud-run-jobs"
  project    = local.project_id
}

# ─── Secret ───────────────────────────────────────────────────────────────────

resource "google_secret_manager_secret" "api_key" {
  secret_id = "tap-travel-perk-api-key"

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

# IMPORTANT: Add the secret value BEFORE running terraform apply for the Cloud Run job.
# Cloud Run will fail at creation time if the secret has no versions.
#   make secret-set PIPELINE=tap-travel-perk SECRET=api-key
# or directly:
#   gcloud secrets versions add tap-travel-perk-api-key \
#     --project=lumapps-business-bi --data-file=- <<< "YOUR_API_KEY"

# ─── Dev Cloud Run Job ────────────────────────────────────────────────────────

# No schedule — trigger manually via GCP Console or:
#   gcloud run jobs execute meltano-tap-travel-perk-dev --region europe-west1 --wait
module "dev" {
  source = "../../../modules/cloud-run-job"

  name       = "meltano-tap-travel-perk-dev"
  project_id = local.project_id
  region     = local.region
  image      = "${local.meltano_img}:dev"
  command    = ["meltano"]
  args       = ["--environment=prod", "run", "tap-travel-perk", "target-bigquery-dev"]

  service_account_email = data.google_service_account.cloud_run_jobs.email

  secret_env_vars = {
    TAP_TRAVEL_PERK__API_KEY = google_secret_manager_secret.api_key.secret_id
  }
}

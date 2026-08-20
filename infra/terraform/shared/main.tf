locals {
  project_id = "lumapps-business-bi"
  region     = "europe-west1"
}

# ─── APIs ─────────────────────────────────────────────────────────────────────

resource "google_project_service" "apis" {
  for_each = toset([
    "run.googleapis.com",               # Cloud Run Jobs
    "cloudscheduler.googleapis.com",    # Cloud Scheduler
    "secretmanager.googleapis.com",     # Secret Manager
    "artifactregistry.googleapis.com",  # Artifact Registry
    "bigquery.googleapis.com",          # BigQuery
    "storage.googleapis.com",           # GCS (meltano state)
    "iam.googleapis.com",               # IAM / service accounts
  ])

  service            = each.value
  disable_on_destroy = false
}

# ─── Artifact Registry ────────────────────────────────────────────────────────

resource "google_artifact_registry_repository" "bi" {
  repository_id = "bi"
  format        = "DOCKER"
  location      = local.region
  description   = "Business BI Docker images"
}

# ─── GCS — Meltano incremental sync state ─────────────────────────────────────

resource "google_storage_bucket" "meltano_state" {
  name                        = "${local.project_id}-meltano-state"
  location                    = "EU"
  uniform_bucket_level_access = true
}

# ─── Service Accounts ─────────────────────────────────────────────────────────

resource "google_service_account" "cloud_run_jobs" {
  account_id   = "bi-cloud-run-jobs"
  display_name = "Business BI — Cloud Run Jobs"
}

resource "google_service_account" "scheduler" {
  account_id   = "bi-cloud-scheduler"
  display_name = "Business BI — Cloud Scheduler"
}

# ─── IAM — Cloud Run jobs SA ─────────────────────────────────────────────────

resource "google_project_iam_member" "cr_bq_data_editor" {
  project = local.project_id
  role    = "roles/bigquery.dataEditor"
  member  = google_service_account.cloud_run_jobs.member
}

resource "google_project_iam_member" "cr_bq_job_user" {
  project = local.project_id
  role    = "roles/bigquery.jobUser"
  member  = google_service_account.cloud_run_jobs.member
}

resource "google_artifact_registry_repository_iam_member" "cr_ar_reader" {
  repository = google_artifact_registry_repository.bi.repository_id
  location   = local.region
  role       = "roles/artifactregistry.reader"
  member     = google_service_account.cloud_run_jobs.member
}

resource "google_storage_bucket_iam_member" "cr_meltano_state" {
  bucket = google_storage_bucket.meltano_state.name
  role   = "roles/storage.objectAdmin"
  member = google_service_account.cloud_run_jobs.member
}

# ─── IAM — Scheduler SA ───────────────────────────────────────────────────────

resource "google_project_iam_member" "scheduler_run_invoker" {
  project = local.project_id
  role    = "roles/run.invoker"
  member  = google_service_account.scheduler.member
}

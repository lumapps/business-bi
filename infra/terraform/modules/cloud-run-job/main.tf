resource "google_cloud_run_v2_job" "job" {
  name             = var.name
  location         = var.region
  project          = var.project_id
  deletion_protection = false

  template {
    template {
      service_account = var.service_account_email
      max_retries     = var.max_retries
      timeout         = "${var.timeout_seconds}s"

      containers {
        image   = var.image
        command = length(var.command) > 0 ? var.command : null
        args    = length(var.args) > 0 ? var.args : null

        dynamic "env" {
          for_each = var.env_vars
          content {
            name  = env.key
            value = env.value
          }
        }

        dynamic "env" {
          for_each = var.secret_env_vars
          content {
            name = env.key
            value_source {
              secret_key_ref {
                secret  = env.value
                version = "latest"
              }
            }
          }
        }

        resources {
          limits = {
            cpu    = var.cpu
            memory = var.memory
          }
        }
      }
    }
  }
}

# Only created when a schedule is provided.
resource "google_cloud_scheduler_job" "trigger" {
  count   = var.schedule != "" ? 1 : 0
  name    = "${var.name}-trigger"
  region  = var.region
  project = var.project_id

  schedule  = var.schedule
  time_zone = "UTC"

  http_target {
    http_method = "POST"
    uri         = "https://run.googleapis.com/v2/${google_cloud_run_v2_job.job.id}:run"

    oauth_token {
      service_account_email = var.scheduler_service_account_email
    }
  }
}

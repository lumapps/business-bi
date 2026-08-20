variable "name" {
  type        = string
  description = "Cloud Run Job name"
}

variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "GCP region"
}

variable "image" {
  type        = string
  description = "Docker image URI"
}

variable "command" {
  type        = list(string)
  description = "Container entrypoint (overrides image ENTRYPOINT)"
  default     = []
}

variable "args" {
  type        = list(string)
  description = "Container arguments"
  default     = []
}

variable "service_account_email" {
  type        = string
  description = "Service account email attached to the Cloud Run Job"
}

variable "scheduler_service_account_email" {
  type        = string
  description = "Service account email used by Cloud Scheduler to trigger the job. Required when schedule is set."
  default     = ""
}

variable "schedule" {
  type        = string
  description = "Cron schedule in UTC. Empty string = no Cloud Scheduler job created (manual trigger only)."
  default     = ""
}

variable "env_vars" {
  type        = map(string)
  description = "Plain environment variables"
  default     = {}
}

variable "secret_env_vars" {
  type        = map(string)
  description = "Map of env var name -> Secret Manager secret ID. Version 'latest' is always used."
  default     = {}
}

variable "max_retries" {
  type        = number
  description = "Maximum retries on task failure"
  default     = 0
}

variable "cpu" {
  type        = string
  description = "CPU allocation"
  default     = "1"
}

variable "memory" {
  type        = string
  description = "Memory allocation"
  default     = "512Mi"
}

variable "timeout_seconds" {
  type        = number
  description = "Maximum task duration in seconds"
  default     = 3600
}

terraform {
  backend "gcs" {
    bucket = "lumapps-business-bi-terraform-state"
    prefix = "terraform/pipelines/tap-travel-perk/prod"
  }
}

terraform {
  backend "gcs" {
    # Run `make tf-bootstrap` once before `terraform init` to create this bucket.
    bucket = "lumapps-business-bi-terraform-state"
    prefix = "terraform/shared"
  }
}

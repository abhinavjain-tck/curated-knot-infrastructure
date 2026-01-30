# Terraform Backend Configuration for Development Environment

terraform {
  backend "gcs" {
    bucket = "curated-knot-development-tf-state"
    prefix = "terraform/state"
  }
}

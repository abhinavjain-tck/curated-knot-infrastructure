# Terraform Backend Configuration for Production Environment

terraform {
  backend "gcs" {
    bucket = "curated-knot-production-tf-state"
    prefix = "terraform/state"
  }
}

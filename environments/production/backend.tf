# Terraform Backend Configuration for Production Environment
# This manages state for curated-knot-prod GCP project

terraform {
  backend "gcs" {
    bucket = "curated-knot-develop-tf-state"
    prefix = "terraform/state"
  }
}

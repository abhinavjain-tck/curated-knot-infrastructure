# Terraform Backend Configuration for Develop Environment

terraform {
  backend "gcs" {
    bucket = "curated-knot-develop-tf-state"
    prefix = "terraform/state"
  }
}

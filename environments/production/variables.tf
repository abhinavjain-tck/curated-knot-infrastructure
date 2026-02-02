# Production Environment Variables
# This manages curated-knot-prod GCP project (current production)

variable "project_id" {
  description = "GCP project ID"
  type        = string
  default     = "curated-knot-prod"
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "asia-south1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

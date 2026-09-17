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

variable "alert_email" {
  description = <<-EOT
    Address that receives comms-worker liveness alerts (C7).

    Deliberately a variable with no default: an alert routed to a wrong or
    unmonitored address is worse than no alert, because it looks like
    coverage. Set it in the environment's tfvars or -var on apply.
  EOT
  type        = string
}

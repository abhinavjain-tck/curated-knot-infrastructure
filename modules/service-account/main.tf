# Service Account Module

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "account_id" {
  description = "Service account ID"
  type        = string
}

variable "display_name" {
  description = "Display name for the service account"
  type        = string
}

variable "description" {
  description = "Description of the service account"
  type        = string
  default     = ""
}

variable "roles" {
  description = "List of IAM roles to grant to the service account"
  type        = list(string)
  default     = []
}

resource "google_service_account" "account" {
  account_id   = var.account_id
  display_name = var.display_name
  description  = var.description
  project      = var.project_id
}

resource "google_project_iam_member" "roles" {
  for_each = toset(var.roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.account.email}"
}

output "email" {
  description = "Service account email"
  value       = google_service_account.account.email
}

output "id" {
  description = "Service account ID"
  value       = google_service_account.account.id
}

output "name" {
  description = "Service account name"
  value       = google_service_account.account.name
}

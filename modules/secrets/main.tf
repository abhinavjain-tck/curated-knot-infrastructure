# Secret Manager Module

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "secrets" {
  description = "Map of secret names to their configurations"
  type = map(object({
    replication_policy = optional(string, "automatic")
    labels             = optional(map(string), {})
  }))
  default = {}
}

resource "google_secret_manager_secret" "secrets" {
  for_each  = var.secrets
  secret_id = each.key
  project   = var.project_id

  replication {
    auto {}
  }

  labels = each.value.labels
}

output "secret_ids" {
  description = "Map of secret names to their IDs"
  value       = { for k, v in google_secret_manager_secret.secrets : k => v.secret_id }
}

output "secret_names" {
  description = "Map of secret names to their resource names"
  value       = { for k, v in google_secret_manager_secret.secrets : k => v.name }
}

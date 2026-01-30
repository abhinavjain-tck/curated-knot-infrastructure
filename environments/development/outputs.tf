# Development Environment Outputs

output "cloud_run_url" {
  description = "URL of the Cloud Run API service"
  value       = module.cloud_run_api.service_url
}

output "cloud_sql_connection" {
  description = "Cloud SQL connection name"
  value       = module.cloud_sql.connection_name
}

output "cloud_sql_ip" {
  description = "Cloud SQL public IP address"
  value       = module.cloud_sql.public_ip_address
}

output "vpc_connector_id" {
  description = "VPC connector ID"
  value       = module.networking.vpc_connector_id
}

output "nat_ips" {
  description = "NAT gateway IP addresses (for MongoDB Atlas whitelisting)"
  value       = module.networking.nat_ips
}

output "artifact_registry_url" {
  description = "Artifact Registry URL for Docker images"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.images.repository_id}"
}

output "api_service_account" {
  description = "API service account email"
  value       = module.api_service_account.email
}

output "github_actions_service_account" {
  description = "GitHub Actions service account email"
  value       = module.github_actions_service_account.email
}

# Cloud SQL PostgreSQL Module

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "instance_name" {
  description = "Name of the Cloud SQL instance"
  type        = string
}

variable "database_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "POSTGRES_15"
}

variable "tier" {
  description = "Machine type tier"
  type        = string
  default     = "db-f1-micro"
}

variable "disk_size" {
  description = "Disk size in GB"
  type        = number
  default     = 10
}

variable "availability_type" {
  description = "Availability type (ZONAL or REGIONAL)"
  type        = string
  default     = "ZONAL"
}

variable "backup_enabled" {
  description = "Enable automated backups"
  type        = bool
  default     = true
}

variable "backup_start_time" {
  description = "Start time for backups (HH:MM format)"
  type        = string
  default     = "03:00"
}

variable "retained_backups" {
  description = "Number of backups to retain"
  type        = number
  default     = 7
}

variable "authorized_networks" {
  description = "List of authorized network CIDRs"
  type        = list(string)
  default     = []
}

variable "labels" {
  description = "Labels to apply to the instance"
  type        = map(string)
  default     = {}
}

resource "google_sql_database_instance" "main" {
  name                = var.instance_name
  database_version    = var.database_version
  region              = var.region
  project             = var.project_id
  deletion_protection = true

  settings {
    tier              = var.tier
    availability_type = var.availability_type
    disk_autoresize   = true
    disk_size         = var.disk_size
    disk_type         = "PD_SSD"
    edition           = "ENTERPRISE"
    pricing_plan      = "PER_USE"

    backup_configuration {
      enabled                        = var.backup_enabled
      start_time                     = var.backup_start_time
      transaction_log_retention_days = 7

      backup_retention_settings {
        retained_backups = var.retained_backups
        retention_unit   = "COUNT"
      }
    }

    ip_configuration {
      ipv4_enabled = true

      dynamic "authorized_networks" {
        for_each = var.authorized_networks
        content {
          value = authorized_networks.value
        }
      }
    }

    user_labels = var.labels
  }
}

output "instance_name" {
  description = "Name of the Cloud SQL instance"
  value       = google_sql_database_instance.main.name
}

output "connection_name" {
  description = "Connection name for Cloud SQL proxy"
  value       = google_sql_database_instance.main.connection_name
}

output "public_ip_address" {
  description = "Public IP address of the instance"
  value       = google_sql_database_instance.main.public_ip_address
}

output "private_ip_address" {
  description = "Private IP address of the instance"
  value       = google_sql_database_instance.main.private_ip_address
}

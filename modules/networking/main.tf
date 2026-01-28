# Networking Module (VPC Connector, NAT, Router)

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "network" {
  description = "VPC network name or self_link"
  type        = string
  default     = "default"
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "vpc_connector_cidr" {
  description = "CIDR range for VPC connector"
  type        = string
  default     = "10.8.0.0/28"
}

variable "create_nat" {
  description = "Whether to create NAT gateway"
  type        = bool
  default     = true
}

variable "nat_ip_count" {
  description = "Number of static IPs for NAT"
  type        = number
  default     = 1
}

variable "nat_log_filter" {
  description = "NAT log filter (ALL, ERRORS_ONLY, TRANSLATIONS_ONLY)"
  type        = string
  default     = "ALL"
}

# VPC Connector for Cloud Run
resource "google_vpc_access_connector" "connector" {
  name          = "vpc-connector"
  project       = var.project_id
  region        = var.region
  network       = var.network
  ip_cidr_range = var.vpc_connector_cidr
}

# Static IP for NAT (for MongoDB Atlas whitelisting)
resource "google_compute_address" "nat_ip" {
  count   = var.create_nat ? var.nat_ip_count : 0
  name    = "${var.name_prefix}-nat-ip${count.index > 0 ? "-${count.index}" : ""}"
  project = var.project_id
  region  = var.region
}

# Cloud Router for NAT
resource "google_compute_router" "router" {
  count   = var.create_nat ? 1 : 0
  name    = "${var.name_prefix}-router"
  project = var.project_id
  region  = var.region
  network = var.network
}

# Cloud NAT
resource "google_compute_router_nat" "nat" {
  count   = var.create_nat ? 1 : 0
  name    = "${var.name_prefix}-nat"
  project = var.project_id
  region  = var.region
  router  = google_compute_router.router[0].name

  nat_ip_allocate_option = "MANUAL_ONLY"
  nat_ips                = google_compute_address.nat_ip[*].self_link

  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = var.nat_log_filter
  }
}

output "vpc_connector_id" {
  description = "VPC connector ID"
  value       = google_vpc_access_connector.connector.id
}

output "vpc_connector_name" {
  description = "VPC connector name"
  value       = google_vpc_access_connector.connector.name
}

output "nat_ips" {
  description = "Static NAT IP addresses"
  value       = google_compute_address.nat_ip[*].address
}

output "router_name" {
  description = "Cloud Router name"
  value       = var.create_nat ? google_compute_router.router[0].name : null
}

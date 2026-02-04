# Development Environment - Main Configuration
# This environment uses the curated-knot-develop GCP project
# Lean configuration for development, demos, and testing

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  name_prefix = "curated-knot"
  labels = {
    environment = var.environment
    managed-by  = "terraform"
    tested-at   = "2026-01-29" # Test change for /plan and /apply comment triggers
  }
}

# Enable required APIs
resource "google_project_service" "apis" {
  for_each = toset([
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "secretmanager.googleapis.com",
    "vpcaccess.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
  ])

  project = var.project_id
  service = each.value

  disable_on_destroy = false
}

# Service Account for API
module "api_service_account" {
  source = "../../modules/service-account"

  project_id   = var.project_id
  account_id   = "${local.name_prefix}-api"
  display_name = "Curated Knot API Service Account (Dev)"
  roles = [
    "roles/cloudsql.client",
    "roles/secretmanager.secretAccessor",
    "roles/logging.logWriter",
    "roles/cloudtrace.agent",
    "roles/monitoring.metricWriter",
  ]

  depends_on = [google_project_service.apis]
}

# Workload Identity Federation for GitHub Actions
# This enables GitHub Actions to authenticate to GCP without long-lived credentials
module "github_actions_workload_identity" {
  source = "../../modules/workload-identity"

  project_id        = var.project_id
  github_repository = "abhinavjain-tck/the-curated-knot"

  service_account_id           = "github-actions-dev"
  service_account_display_name = "GitHub Actions (Development)"
  service_account_roles = [
    "roles/run.admin",
    "roles/storage.admin",
    "roles/secretmanager.secretAccessor",
    "roles/iam.serviceAccountUser",
    "roles/iam.workloadIdentityPoolAdmin", # Required for Terraform to manage workload identity
    "roles/cloudsql.client",
    "roles/artifactregistry.writer",
  ]

  depends_on = [google_project_service.apis]
}

# Networking (VPC Connector, NAT, Router)
module "networking" {
  source = "../../modules/networking"

  project_id         = var.project_id
  region             = var.region
  name_prefix        = local.name_prefix
  network            = "default"
  vpc_connector_cidr = "10.9.0.0/28" # Different CIDR from production
  create_nat         = true
  nat_ip_count       = 1

  depends_on = [google_project_service.apis]
}

# Cloud SQL PostgreSQL - LEAN DEVELOPMENT SPECS
module "cloud_sql" {
  source = "../../modules/cloud-sql"

  project_id          = var.project_id
  region              = var.region
  instance_name       = "${local.name_prefix}-db"
  database_version    = "POSTGRES_15"
  tier                = "db-f1-micro" # Smallest tier (~$7/month) for development
  disk_size           = 10            # Minimal disk for dev
  availability_type   = "ZONAL"       # No HA needed for dev
  backup_enabled      = true
  retained_backups    = 3  # Fewer backups for dev
  authorized_networks = [] # Access via VPC connector only
  labels              = local.labels

  depends_on = [google_project_service.apis]
}

# Artifact Registry for Docker images
resource "google_artifact_registry_repository" "images" {
  location      = var.region
  repository_id = "${local.name_prefix}-images"
  description   = "Docker images for Curated Knot API (Development)"
  format        = "DOCKER"
  project       = var.project_id

  labels = local.labels

  depends_on = [google_project_service.apis]
}

# Cloud Run API Service - LEAN DEVELOPMENT SPECS
module "cloud_run_api" {
  source = "../../modules/cloud-run"

  project_id            = var.project_id
  region                = var.region
  service_name          = "${local.name_prefix}-api"
  image                 = "gcr.io/cloudrun/hello" # Placeholder until API is built
  service_account_email = module.api_service_account.email
  vpc_connector_id      = module.networking.vpc_connector_id
  cloud_sql_connection  = module.cloud_sql.connection_name
  environment           = var.environment
  allowed_origins       = "https://develop.thecuratedknot.com,https://develop-admin.thecuratedknot.com"
  allow_unauthenticated = false # Org policy prevents allUsers access

  cpu           = "1"
  memory        = "512Mi"
  max_instances = 5 # Lower limit for development
  min_instances = 0 # Scale to zero when not in use (SAVES MONEY!)

  secrets = {
    DATABASE_URL        = "database-url"
    PRISMA_DATABASE_URL = "prisma-database-url"
    MONGODB_URI         = "mongodb-uri"
    SENTRY_DSN          = "sentry-dsn"
    CLERK_SECRET_KEY    = "clerk-secret-key"
  }

  depends_on = [
    google_project_service.apis,
    module.api_service_account,
    module.networking,
    module.cloud_sql,
    google_artifact_registry_repository.images,
  ]
}

# Static Assets Bucket - LEAN DEVELOPMENT SPECS
module "static_assets" {
  source = "../../modules/storage"

  project_id               = var.project_id
  location                 = upper(var.region)
  name                     = "${local.name_prefix}-dev-static-assets"
  storage_class            = "STANDARD"
  versioning_enabled       = false # No versioning needed for dev
  public_access_prevention = "enforced"
  labels                   = local.labels

  cors = [
    {
      origin          = ["https://develop.thecuratedknot.com", "https://develop-admin.thecuratedknot.com"]
      method          = ["GET", "HEAD"]
      response_header = ["Content-Type"]
      max_age_seconds = 3600
    }
  ]

  lifecycle_rules = [
    {
      action = {
        type = "Delete"
      }
      condition = {
        age = 90 # Auto-delete old dev assets after 90 days
      }
    }
  ]

  depends_on = [google_project_service.apis]
}

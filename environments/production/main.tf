# Production Environment - Main Configuration
# This environment will use a new curated-knot-production GCP project

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
  display_name = "Curated Knot API Service Account"
  roles = [
    "roles/cloudsql.client",
    "roles/secretmanager.secretAccessor",
    "roles/logging.logWriter",
    "roles/cloudtrace.agent",
    "roles/monitoring.metricWriter",
  ]

  depends_on = [google_project_service.apis]
}

# Service Account for GitHub Actions
module "github_actions_service_account" {
  source = "../../modules/service-account"

  project_id   = var.project_id
  account_id   = "github-actions"
  display_name = "GitHub Actions Deployer"
  roles = [
    "roles/run.admin",
    "roles/iam.serviceAccountUser",
    "roles/artifactregistry.writer",
    "roles/storage.admin",
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
  vpc_connector_cidr = "10.8.0.0/28"
  create_nat         = true
  nat_ip_count       = 1

  depends_on = [google_project_service.apis]
}

# Cloud SQL PostgreSQL - Production specs
module "cloud_sql" {
  source = "../../modules/cloud-sql"

  project_id        = var.project_id
  region            = var.region
  instance_name     = "${local.name_prefix}-db"
  database_version  = "POSTGRES_15"
  tier              = "db-custom-1-3840" # 1 vCPU, 3.75 GB RAM for production
  disk_size         = 20
  availability_type = "ZONAL" # Consider REGIONAL for HA in future
  backup_enabled    = true
  retained_backups  = 14 # Keep more backups in production
  authorized_networks = [
    # NAT IP for outbound connections
  ]
  labels = local.labels

  depends_on = [google_project_service.apis]
}

# Artifact Registry for Docker images
resource "google_artifact_registry_repository" "images" {
  location      = var.region
  repository_id = "${local.name_prefix}-images"
  description   = "Docker images for Curated Knot API"
  format        = "DOCKER"
  project       = var.project_id

  labels = local.labels

  depends_on = [google_project_service.apis]
}

# Cloud Run API Service - Production specs
module "cloud_run_api" {
  source = "../../modules/cloud-run"

  project_id            = var.project_id
  region                = var.region
  service_name          = "${local.name_prefix}-api"
  image                 = "${var.region}-docker.pkg.dev/${var.project_id}/${local.name_prefix}-images/${local.name_prefix}-api:main"
  service_account_email = module.api_service_account.email
  vpc_connector_id      = module.networking.vpc_connector_id
  cloud_sql_connection  = module.cloud_sql.connection_name
  environment           = var.environment
  allowed_origins       = "https://thecuratedknot.com,https://admin.thecuratedknot.com"

  cpu           = "1"
  memory        = "512Mi"
  max_instances = 20 # Higher limit for production
  min_instances = 1  # Keep at least 1 instance warm for production

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

# Static Assets Bucket
module "static_assets" {
  source = "../../modules/storage"

  project_id               = var.project_id
  location                 = upper(var.region)
  name                     = "${local.name_prefix}-prod-static-assets"
  storage_class            = "STANDARD"
  versioning_enabled       = true # Enable versioning in production
  public_access_prevention = "enforced"
  labels                   = local.labels

  cors = [
    {
      origin          = ["https://thecuratedknot.com", "https://admin.thecuratedknot.com"]
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
        num_newer_versions = 5 # Keep last 5 versions
      }
    }
  ]

  depends_on = [google_project_service.apis]
}

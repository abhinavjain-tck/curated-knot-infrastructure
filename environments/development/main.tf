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
    "storage.googleapis.com",
    # C7: the worker uptime check + log-based paralysis alert.
    "monitoring.googleapis.com",
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
    "roles/storage.objectAdmin", # GCS signed URL generation + object management
  ]

  depends_on = [google_project_service.apis]
}

# Allow the API SA to sign its own blobs (required for GCS V4 signed URLs).
# Scoped to the SA itself, NOT project-wide — prevents impersonation of other SAs.
resource "google_service_account_iam_member" "api_self_sign" {
  service_account_id = module.api_service_account.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${module.api_service_account.email}"

  depends_on = [module.api_service_account]
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
    "roles/iam.roleAdmin",                 # Required for Terraform to manage custom IAM roles
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
  retained_backups    = 3             # Fewer backups for dev
  authorized_networks = ["0.0.0.0/0"] # Open for Vercel serverless access (see docs/05-security/database-security.md)
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
  allow_unauthenticated = true # Public access; app-level JWT auth handles authorization

  cpu           = "1"
  memory        = "512Mi"
  max_instances = 5 # Lower limit for development
  min_instances = 0 # Scale to zero when not in use (SAVES MONEY!)

  env_vars = {
    GCS_BUCKET_NAME = module.user_uploads.name
    GCS_PROJECT_ID  = var.project_id
  }

  secrets = {
    DATABASE_URL        = "database-url"
    PRISMA_DATABASE_URL = "prisma-database-url"
    SENTRY_DSN          = "sentry-dsn"
    API_JWT_SECRET      = "api-jwt-secret"
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

# User Uploads Bucket - Wedding images, profile photos, etc.
module "user_uploads" {
  source = "../../modules/storage"

  project_id               = var.project_id
  location                 = upper(var.region)
  name                     = "${local.name_prefix}-dev-uploads"
  storage_class            = "STANDARD"
  versioning_enabled       = false
  public_access_prevention = "inherited" # Must be inherited for public_read
  public_read              = true        # Wedding images must be publicly viewable
  labels                   = local.labels

  cors = [
    {
      origin          = ["http://localhost:3001", "https://develop.thecuratedknot.com"]
      method          = ["PUT", "GET", "HEAD"]
      response_header = ["Content-Type", "Content-Length"]
      max_age_seconds = 3600
    }
  ]

  lifecycle_rules = [
    {
      action = {
        type = "Delete"
      }
      condition = {
        age = 90 # Auto-delete old dev uploads after 90 days
      }
    }
  ]

  depends_on = [google_project_service.apis]
}

# ─── Cloud Run Comms Worker ────────────────────────────────────────────────
#
# The ONLY process that runs pg-boss (comms 02 §7.3). Same image as the API,
# different container command.
#
# `args` overrides the image's CMD and leaves its ENTRYPOINT (`dumb-init --`)
# in place on purpose: dumb-init is what forwards SIGTERM to node, and the
# worker's graceful drain — "deploy during an in-flight send: zero stranded
# rows" — depends on receiving it.
#
# TF owns the SHAPE of this service; CI only pushes the image tag (C3). Do not
# add --set-secrets or --args to the deploy workflow for the worker: unlike the
# API, whose secrets live in the workflow, this service's secrets live here.
module "cloud_run_worker" {
  source = "../../modules/cloud-run"

  project_id            = var.project_id
  region                = var.region
  service_name          = "${local.name_prefix}-comms-worker"
  image                 = "gcr.io/cloudrun/hello" # CI replaces this (C3)
  service_account_email = module.api_service_account.email
  vpc_connector_id      = module.networking.vpc_connector_id
  cloud_sql_connection  = module.cloud_sql.connection_name
  environment           = var.environment

  args = ["node", "dist/worker.js"]

  # Not an HTTP server beyond /health. Empty rather than making a
  # security-relevant variable optional for the two live API services;
  # nothing the worker runs reads ALLOWED_ORIGINS.
  allowed_origins = ""

  # /health is public so Cloud Monitoring's uptime checkers can reach it.
  # Cloud Run IAM is per-SERVICE, not per-path, so the alternative is a
  # permanently-failing uptime check — an alert everyone learns to ignore,
  # which is the failure C7 exists to prevent. The route returns
  # {"status","role"} and nothing else; worker.ts 404s every other path.
  allow_unauthenticated = true

  # One instance, always. Two would mean two pg-boss pollers: double the
  # connection draw (C6) and two independent ESP token buckets instead of one.
  max_instances = 1

  # DEV ONLY: scale to zero and let the CPU throttle. Saves the standing cost,
  # and dev accepts late drains.
  #
  # ⚠️ This means dev exhibits the very throttling the worker exists to avoid,
  # so A7's "zero stranded rows on deploy" criterion is NOT verifiable here.
  # Verify that one locally against real Postgres, or flip these two values
  # temporarily for the verification window.
  min_instances = 0
  cpu_idle      = true

  cpu    = "1"
  memory = "512Mi" # Boots the full Nest DI container, same as the API

  # Serves only /health; 80 is meaningless for a non-server.
  max_request_concurrency = 1

  env_vars = {
    # Without this the email module binds the STUB provider: the worker would
    # drain the queue and send nothing while reporting success.
    EMAIL_PROVIDER     = "resend"
    EMAIL_FROM_ADDRESS = "hello@send.thecuratedknot.com"
    EMAIL_FROM_NAME    = "The Curated Knot"
    # StorageModule boots as part of AppModule.
    GCS_BUCKET_NAME = module.user_uploads.name
    GCS_PROJECT_ID  = var.project_id
  }

  # Names only — values live in Secret Manager, created out of band.
  # A referenced secret that does not exist fails the revision at CREATE time,
  # which is the loud failure you want.
  secrets = {
    DATABASE_URL                 = "database-url"
    PRISMA_DATABASE_URL          = "prisma-database-url"
    SENTRY_DSN                   = "sentry-dsn"
    API_JWT_SECRET               = "api-jwt-secret"
    RESEND_API_KEY               = "resend-api-key"
    RESEND_WEBHOOK_SECRET        = "resend-webhook-secret"
    COMMS_RECIPIENT_HASH_PEPPERS = "comms-recipient-hash-peppers"
  }

  depends_on = [
    google_project_service.apis,
    module.api_service_account,
    module.networking,
    module.cloud_sql,
    google_artifact_registry_repository.images,
    module.user_uploads,
  ]
}

# ─── Worker Liveness Monitoring (comms C7) ─────────────────────────────────
#
# The one detection path that survives worker death: the reconciler and the
# FAILED-spike alert both run INSIDE the worker, so nothing in-process can
# report that the worker is gone.
module "worker_monitoring" {
  source = "../../modules/monitoring"

  project_id          = var.project_id
  environment         = var.environment
  worker_service_name = "${local.name_prefix}-comms-worker"
  # The uptime check's monitored_resource wants a bare host, no scheme.
  worker_host = replace(module.cloud_run_worker.service_url, "https://", "")
  alert_email = var.alert_email

  depends_on = [
    google_project_service.apis,
    module.cloud_run_worker,
  ]
}


# Production Environment - Main Configuration
# This environment uses the existing curated-knot-prod GCP project

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

# Grant storage.objectAdmin scoped to the uploads bucket only (not project-wide)
resource "google_storage_bucket_iam_member" "api_uploads_admin" {
  bucket = module.user_uploads.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${module.api_service_account.email}"

  depends_on = [module.api_service_account, module.user_uploads]
}

# Allow the API SA to sign its own blobs (required for GCS V4 signed URLs).
# Scoped to the SA itself, NOT project-wide.
resource "google_service_account_iam_member" "api_self_sign" {
  service_account_id = module.api_service_account.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${module.api_service_account.email}"

  depends_on = [module.api_service_account]
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
    "roles/iam.roleAdmin", # Required for Terraform to manage custom IAM roles
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

# Cloud SQL PostgreSQL
module "cloud_sql" {
  source = "../../modules/cloud-sql"

  project_id          = var.project_id
  region              = var.region
  instance_name       = "${local.name_prefix}-db"
  database_version    = "POSTGRES_15"
  tier                = "db-f1-micro" # Match existing
  disk_size           = 10            # Match existing
  availability_type   = "ZONAL"
  backup_enabled      = true
  retained_backups    = 7             # Match existing
  authorized_networks = ["0.0.0.0/0"] # Open for Vercel serverless access (see docs/05-security/database-security.md)
  labels              = {}            # No labels currently

  depends_on = [google_project_service.apis]
}

# Artifact Registry for Docker images
resource "google_artifact_registry_repository" "images" {
  location      = var.region
  repository_id = "${local.name_prefix}-images"
  description   = "Docker images for The Curated Knot" # Match existing
  format        = "DOCKER"
  project       = var.project_id

  labels = {} # No labels currently (will add in future)

  depends_on = [google_project_service.apis]
}

# Cloud Run API Service
# NOTE: This currently manages the live production deployment
# The environment variable is set to "production" to match existing state
module "cloud_run_api" {
  source = "../../modules/cloud-run"

  project_id            = var.project_id
  region                = var.region
  service_name          = "${local.name_prefix}-api"
  image                 = "${var.region}-docker.pkg.dev/${var.project_id}/${local.name_prefix}-images/${local.name_prefix}-api:main"
  service_account_email = module.api_service_account.email
  vpc_connector_id      = module.networking.vpc_connector_id
  cloud_sql_connection  = module.cloud_sql.connection_name
  environment           = "production" # Keep as production to match existing state
  allowed_origins       = "https://thecuratedknot.com,https://admin.thecuratedknot.com"

  cpu           = "1"
  memory        = "512Mi"
  max_instances = 20 # Higher limit for production
  min_instances = 1  # Keep at least 1 instance warm for production

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
    module.user_uploads,
  ]
}

# Static Assets Bucket
module "static_assets" {
  source = "../../modules/storage"

  project_id               = var.project_id
  location                 = upper(var.region)
  name                     = "${local.name_prefix}-static-assets" # Match existing
  storage_class            = "STANDARD"
  versioning_enabled       = false       # Match existing
  public_access_prevention = "inherited" # Match existing state
  labels                   = {}          # No labels currently

  cors = [] # No CORS currently configured

  depends_on = [google_project_service.apis]
}

# User Uploads Bucket - Wedding images, profile photos, etc.
module "user_uploads" {
  source = "../../modules/storage"

  project_id               = var.project_id
  location                 = upper(var.region)
  name                     = "${local.name_prefix}-uploads"
  storage_class            = "STANDARD"
  versioning_enabled       = false
  public_access_prevention = "inherited" # Must be inherited for public_read
  public_read              = true        # Wedding images must be publicly viewable
  labels                   = local.labels

  cors = [
    {
      origin          = ["https://thecuratedknot.com", "https://www.thecuratedknot.com"]
      method          = ["PUT", "GET", "HEAD"]
      response_header = ["Content-Type", "Content-Length"]
      max_age_seconds = 3600
    }
  ]

  # No auto-delete lifecycle — wedding photos are permanent
  lifecycle_rules = []

  depends_on = [google_project_service.apis]
}

# ─── Cloud Run Comms Worker ────────────────────────────────────────────────
#
# The ONLY process that runs pg-boss (comms 02 §7.3). Same image as the API,
# different container command.
#
# `args` overrides the image's CMD and leaves its ENTRYPOINT (`dumb-init --`)
# in place on purpose: dumb-init forwards SIGTERM to node, and the worker's
# graceful drain — "deploy during an in-flight send: zero stranded rows" —
# depends on receiving it.
#
# TF owns the SHAPE; CI only pushes the image tag (C3). Do NOT add
# --set-secrets or --args to the deploy workflow for this service: unlike the
# API, whose secrets live in the workflow, the worker's live here.
module "cloud_run_worker" {
  source = "../../modules/cloud-run"

  project_id            = var.project_id
  region                = var.region
  service_name          = "${local.name_prefix}-comms-worker"
  image                 = "${var.region}-docker.pkg.dev/${var.project_id}/${local.name_prefix}-images/${local.name_prefix}-api:main"
  service_account_email = module.api_service_account.email
  vpc_connector_id      = module.networking.vpc_connector_id
  cloud_sql_connection  = module.cloud_sql.connection_name
  environment           = var.environment

  args = ["node", "dist/worker.js"]

  # Not an HTTP server beyond /health. Empty rather than making a
  # security-relevant variable optional for the two live API services.
  allowed_origins = ""

  # /health is public so Cloud Monitoring's uptime checkers can reach it.
  # Cloud Run IAM is per-SERVICE, not per-path, so the alternative is a
  # permanently-failing uptime check — an alert everyone learns to ignore,
  # which is the failure C7 exists to prevent.
  allow_unauthenticated = true

  # ⚠️ THE POINT OF A SEPARATE SERVICE. With cpu_idle = true Cloud Run
  # throttles a poller to ~1% CPU between requests, so the queue barely
  # drains (02 §7.3 records this as a known trap). This is the one setting
  # that must not be "optimised" back.
  cpu_idle = false

  # min = max = 1, both load-bearing. min 1 keeps the poller alive with no
  # inbound traffic; max 1 makes a second poller structurally impossible —
  # two would double the connection draw (C6) and split the ESP token bucket.
  min_instances = 1
  max_instances = 1

  cpu    = "1"      # cpu_idle=false requires >= 1 vCPU
  memory = "512Mi"  # Boots the full Nest DI container, same as the API

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
  # A referenced secret that does not exist fails the revision at CREATE time.
  # NOTE a malformed one does NOT: the worker boots green and every job fails
  # in a retry loop, so first-deploy verification must be a real send.
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


# Cloud Run Service Module

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "service_name" {
  description = "Name of the Cloud Run service"
  type        = string
}

variable "image" {
  description = "Container image to deploy"
  type        = string
}

variable "service_account_email" {
  description = "Service account email for the Cloud Run service"
  type        = string
}

variable "vpc_connector_id" {
  description = "VPC connector ID for private networking"
  type        = string
}

variable "cloud_sql_connection" {
  description = "Cloud SQL instance connection name"
  type        = string
}

variable "environment" {
  description = "Environment name (develop/production)"
  type        = string
}

variable "allowed_origins" {
  description = "Comma-separated list of allowed CORS origins"
  type        = string
}

variable "cpu" {
  description = "CPU limit for the container"
  type        = string
  default     = "1"
}

variable "memory" {
  description = "Memory limit for the container"
  type        = string
  default     = "512Mi"
}

variable "max_instances" {
  description = "Maximum number of instances"
  type        = number
  default     = 10
}

variable "min_instances" {
  description = "Minimum number of instances (0 for scale to zero)"
  type        = number
  default     = 0
}

variable "env_vars" {
  description = "Map of plain (non-secret) environment variable names to values. Caller must avoid collisions with static vars (NODE_ENV, ENVIRONMENT, ALLOWED_ORIGINS) and secrets."
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Map of environment variable names to secret names"
  type        = map(string)
  default     = {}
}

variable "allow_unauthenticated" {
  description = "Allow unauthenticated access (allUsers)"
  type        = bool
  default     = true
}

# ─── Worker support (comms C1) ──────────────────────────────────────────────
# Every default below MATCHES the value this module hardcoded before, so
# `terraform plan` on the two live API services is a no-diff. That no-diff is
# the acceptance criterion — a changed default here is a silent production
# change to both API services.

variable "args" {
  description = <<-EOT
    Overrides the image's CMD (Docker semantics: `args` = CMD, `command` =
    ENTRYPOINT). Used by the comms worker to run `dist/worker.js` from the
    SAME image as the API.

    Deliberately overrides CMD and NOT ENTRYPOINT: the Dockerfile's
    `ENTRYPOINT ["dumb-init", "--"]` is what forwards SIGTERM to node, and the
    worker's graceful drain depends on it. Setting `command` would drop
    dumb-init and make node PID 1.

    Empty list = omit the attribute entirely (see the dynamic block below).
    Cloud Run reads an EXPLICIT empty list as "clear the image's CMD", which
    would leave the API running `dumb-init --` with no program.
  EOT
  type        = list(string)
  default     = []
}

variable "command" {
  description = "Overrides the image's ENTRYPOINT. Escape hatch only — the worker leaves this empty so dumb-init survives. Same empty-list semantics as `args`."
  type        = list(string)
  default     = []
}

variable "cpu_idle" {
  description = <<-EOT
    false = CPU always allocated. Default true preserves the API's
    request-scoped billing.

    The comms worker MUST set false: it is a poller, and with cpu_idle=true
    Cloud Run throttles it to ~1% CPU between requests, so the queue barely
    drains (comms 02 §7.3 records this as a known trap).
  EOT
  type        = bool
  default     = true
}

variable "ingress" {
  description = "Ingress setting. Default matches the value this module hardcoded. Note this is orthogonal to `allow_unauthenticated`: ingress controls who can reach the service, IAM controls who may invoke it."
  type        = string
  default     = "INGRESS_TRAFFIC_ALL"
}

variable "max_request_concurrency" {
  description = "Concurrent requests per instance. Default 80 matches the previous hardcoded value; the worker serves only /health so it uses 1."
  type        = number
  default     = 80
}

resource "google_cloud_run_v2_service" "api" {
  name     = var.service_name
  location = var.region
  project  = var.project_id
  ingress  = var.ingress

  template {
    service_account = var.service_account_email
    timeout         = "300s"

    max_instance_request_concurrency = var.max_request_concurrency

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    containers {
      image = var.image

      # NULL when empty, deliberately. `command` and `args` are optional LIST
      # ATTRIBUTES (not blocks) in provider 5.x, and Terraform omits an
      # attribute set to null — which keeps the image's own ENTRYPOINT/CMD in
      # force and makes the two live API services a plan no-diff.
      #
      # Passing the list directly would emit `args = []`, and Cloud Run reads
      # an EXPLICIT empty list as "clear the image's CMD": both API services
      # would then run `dumb-init --` with no program and crash-loop.
      command = length(var.command) > 0 ? var.command : null
      args    = length(var.args) > 0 ? var.args : null

      ports {
        container_port = 8080
        name           = "http1"
      }

      resources {
        cpu_idle          = var.cpu_idle
        startup_cpu_boost = true
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
      }

      # Static environment variables
      # Always use NODE_ENV=production for deployed environments
      # This ensures the app uses /tmp for writable paths (like GraphQL schema)
      # Local development uses NODE_ENV=development
      env {
        name  = "NODE_ENV"
        value = "production"
      }

      # ENVIRONMENT tracks which deployment environment (develop/production)
      # Use this for logging, feature flags, etc. instead of NODE_ENV
      env {
        name  = "ENVIRONMENT"
        value = var.environment
      }

      env {
        name  = "ALLOWED_ORIGINS"
        value = var.allowed_origins
      }

      # Plain environment variables (non-secret config)
      dynamic "env" {
        for_each = var.env_vars
        content {
          name  = env.key
          value = env.value
        }
      }

      # Secret environment variables
      dynamic "env" {
        for_each = var.secrets
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = env.value
              version = "latest"
            }
          }
        }
      }

      startup_probe {
        failure_threshold     = 1
        initial_delay_seconds = 0
        period_seconds        = 240
        timeout_seconds       = 240
        tcp_socket {
          port = 8080
        }
      }

      volume_mounts {
        mount_path = "/cloudsql"
        name       = "cloudsql"
      }
    }

    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [var.cloud_sql_connection]
      }
    }

    vpc_access {
      connector = var.vpc_connector_id
      egress    = "ALL_TRAFFIC"
    }
  }

  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }

  lifecycle {
    # ONLY the image is ignored, and that is deliberate.
    #
    # CI owns the image tag (it changes every deploy, and terraform must not
    # fight it). Everything else — scaling especially — is terraform's, so it
    # is NOT listed here: a `plan` after a deploy SHOULD show a diff if
    # something moved the scaling out of band, and `apply` should put it back.
    #
    # Do NOT add `template[0].scaling` here to silence such a diff. That would
    # make a stray `gcloud run deploy --max-instances` win permanently and
    # silently, which is the bug this workstream just removed: TF said
    # min 1 / max 20 and the workflow said min 0 / max 10, and the live value
    # was whichever ran last. The diff is the alarm, not the problem.
    ignore_changes = [
      template[0].containers[0].image,
      client,
      client_version,
    ]
  }
}

# Make the service publicly accessible (optional)
resource "google_cloud_run_service_iam_member" "public" {
  count    = var.allow_unauthenticated ? 1 : 0
  location = google_cloud_run_v2_service.api.location
  project  = google_cloud_run_v2_service.api.project
  service  = google_cloud_run_v2_service.api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

output "service_url" {
  description = "URL of the Cloud Run service"
  value       = google_cloud_run_v2_service.api.uri
}

output "service_name" {
  description = "Name of the Cloud Run service"
  value       = google_cloud_run_v2_service.api.name
}

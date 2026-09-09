# Worker Liveness Monitoring (comms C7)
#
# The reconciler AND the FAILED-spike alert both run INSIDE the worker, so if
# the worker dies nothing sends and no alert fires. This module is the one
# detection path that survives worker death — it runs in Cloud Monitoring,
# outside the process it watches.
#
# TWO alerts, deliberately, because they detect different failures:
#
#   1. The uptime check proves the HTTP server answers. It catches process
#      death, a crash-loop, a failed revision.
#   2. The log-absence check proves the CRONS are running. It catches
#      PARALYSIS — a worker whose socket is open but whose poller is throttled
#      (the cpu_idle trap in 02 §7.3) or wedged.
#
# An uptime check alone would show green for a throttled worker, which is the
# exact failure the §7.3 trap section is about. C7 as written specifies only
# the uptime check; the second alert is what actually closes the gap.

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "environment" {
  description = "Deployment environment (development/production)"
  type        = string
}

variable "worker_service_name" {
  description = "Cloud Run service name of the comms worker"
  type        = string
}

variable "worker_host" {
  description = "Bare host of the worker's URL (no scheme), for the uptime check's monitored_resource"
  type        = string
}

variable "alert_email" {
  description = "Address that receives worker-liveness alerts"
  type        = string
}

variable "uptime_period" {
  description = "How often to probe /health. 300s is the minimum Cloud Monitoring accepts."
  type        = string
  default     = "300s"
}

variable "reconcile_silence_seconds" {
  description = <<-EOT
    How long without a reconciler log line before alerting.

    The reconciler cron is hourly, so this must exceed 3600s or it fires
    between healthy runs. 5400s (90 min) gives one full missed run plus
    slack for a slow boot or a deploy window.
  EOT
  type        = number
  default     = 5400
}

resource "google_monitoring_notification_channel" "email" {
  project      = var.project_id
  display_name = "Comms worker alerts (${var.environment})"
  type         = "email"

  labels = {
    email_address = var.alert_email
  }
}

# ─── 1. Is the process alive? ───────────────────────────────────────────────
resource "google_monitoring_uptime_check_config" "worker" {
  project      = var.project_id
  display_name = "${var.worker_service_name} liveness"
  timeout      = "10s"
  period       = var.uptime_period

  http_check {
    path         = "/health"
    port         = 443
    use_ssl      = true
    validate_ssl = true

    accepted_response_status_codes {
      status_class = "STATUS_CLASS_2XX"
    }
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      host       = var.worker_host
      project_id = var.project_id
    }
  }
}

resource "google_monitoring_alert_policy" "worker_down" {
  project      = var.project_id
  display_name = "Comms worker is DOWN (${var.environment})"
  combiner     = "OR"

  documentation {
    content   = <<-EOT
      The comms worker's /health stopped answering.

      Nothing is sending while this is true: the worker is the only pg-boss
      consumer. Queued messages are NOT lost — they wait in pgboss.job and
      drain when it comes back — but password resets and OTPs are not
      arriving, so treat it as user-facing.

      Check: Cloud Run revision status, then the boot logs. A revision that
      fails its startup probe usually means a missing or malformed secret
      (COMMS_RECIPIENT_HASH_PEPPERS must be a JSON keymap, not a bare string).
    EOT
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "uptime check failing"

    condition_threshold {
      filter = join(" AND ", [
        "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\"",
        "resource.type=\"uptime_url\"",
        "metric.label.check_id=\"${google_monitoring_uptime_check_config.worker.uptime_check_id}\"",
      ])
      comparison      = "COMPARISON_LT"
      threshold_value = 1
      duration        = "0s"

      aggregations {
        alignment_period     = "1200s"
        per_series_aligner   = "ALIGN_NEXT_OLDER"
        cross_series_reducer = "REDUCE_COUNT_FALSE"
        group_by_fields      = ["resource.label.host"]
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]

  alert_strategy {
    auto_close = "3600s"
  }
}

# ─── 2. Is the poller actually working? ─────────────────────────────────────
#
# A throttled worker answers /health while draining nothing. This metric
# counts reconciler completions; absence of them is the real liveness signal.
resource "google_logging_metric" "reconcile_runs" {
  project = var.project_id
  name    = "${var.worker_service_name}-reconcile-runs"
  # Matches on TEXT, not jsonPayload, deliberately.
  #
  # worker.ts uses Nest's default `Logger`, which writes plain text to stdout,
  # so Cloud Logging populates textPayload — a `jsonPayload.event=...` filter
  # would match nothing and this alert would fire permanently on day one.
  #
  # If the worker is ever switched to a JSON logger (A11's redaction work is
  # the likely trigger), change this to
  # `jsonPayload.event="comm.reconcile"` and re-verify in Logs Explorer
  # BEFORE relying on the alert again.
  filter = join(" AND ", [
    "resource.type=\"cloud_run_revision\"",
    "resource.labels.service_name=\"${var.worker_service_name}\"",
    "textPayload:\"comm.reconcile\"",
  ])

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}

resource "google_monitoring_alert_policy" "worker_paralysed" {
  project      = var.project_id
  display_name = "Comms worker is not RECONCILING (${var.environment})"
  combiner     = "OR"

  documentation {
    content   = <<-EOT
      The worker is answering /health but has not logged a reconciler run in
      over 90 minutes. The cron is hourly, so it should have.

      This is the failure an uptime check cannot see: the socket is open and
      the process is alive, but the poller is not doing work. The usual cause
      is CPU throttling — `cpu_idle` must be false on this service (02 §7.3),
      and it is the one setting that must never be "optimised" back.

      Other causes: pg-boss lost its connection, or the job queue is wedged
      behind a poison job.
    EOT
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "no reconciler run in the window"

    condition_absent {
      filter   = "metric.type=\"logging.googleapis.com/user/${google_logging_metric.reconcile_runs.name}\" AND resource.type=\"cloud_run_revision\""
      duration = "${var.reconcile_silence_seconds}s"

      aggregations {
        alignment_period   = "600s"
        per_series_aligner = "ALIGN_COUNT"
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]

  alert_strategy {
    auto_close = "3600s"
  }
}

output "notification_channel_id" {
  description = "Email channel other alert policies can reuse"
  value       = google_monitoring_notification_channel.email.id
}

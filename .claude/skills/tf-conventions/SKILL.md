---
name: tf-conventions
description: >
  Terraform and GCP infrastructure conventions for The Curated Knot.
  Use when writing or modifying Terraform files, creating new modules,
  or adding GCP resources. Covers module design, naming, labeling,
  environment management, and GCP-specific patterns.
---

# Terraform Conventions

## Project Structure

```
curated-knot-infrastructure/
├── modules/                    # Reusable Terraform modules
│   ├── cloud-run/             # Cloud Run service deployment
│   ├── cloud-sql/             # PostgreSQL database
│   ├── networking/            # VPC, NAT, Router
│   ├── service-account/       # IAM service accounts
│   ├── storage/               # Cloud Storage buckets
│   ├── secrets/               # Secret Manager
│   └── workload-identity/     # GitHub OIDC federation
├── environments/
│   ├── development/           # curated-knot-develop project
│   └── production/            # curated-knot-prod project
└── scripts/                   # Helper automation
```

## GCP Projects

| Environment | Project ID | Region | State Bucket |
|-------------|-----------|--------|-------------|
| Development | `curated-knot-develop` | `asia-south1` | `curated-knot-development-tf-state` |
| Production | `curated-knot-prod` | `asia-south1` | `curated-knot-production-tf-state` |

## Naming Convention

**Pattern**: `curated-knot-{resource}[-{variant}]`

Examples:
- `curated-knot-api` — Cloud Run service
- `curated-knot-db` — Cloud SQL instance
- `curated-knot-dev-static-assets` — Dev storage bucket
- `curated-knot-static-assets` — Prod storage bucket
- `curated-knot-images` — Artifact Registry
- `curated-knot-nat-ip` — NAT static IP
- `vpc-connector` — VPC Access Connector

Use `local.name_prefix = "curated-knot"` in environment configs.

## Labels

All resources must have:
```hcl
labels = {
  environment = var.environment    # "development" or "production"
  managed-by  = "terraform"
}
```

## Module Design

Each module has a single `main.tf` with variables, resources, and outputs inline.

**Variable rules:**
- All variables have `description`
- Default values for environment-specific settings
- Proper `type` constraints
- Validation blocks for critical inputs

**Output rules:**
- Expose what consumers need (IDs, names, URLs)
- Add `description` to outputs

**Lifecycle:**
- `ignore_changes` for immutable fields (e.g., Cloud Run image tags)
- `prevent_destroy` for critical resources (databases, state buckets)
- `depends_on` explicit for API enablement before resource creation

## Environment Configuration

Each environment directory has:
- `backend.tf` — GCS state backend
- `main.tf` — Module calls with environment-specific values
- `variables.tf` — Variable declarations
- `outputs.tf` — Output declarations

**Dev vs Prod differences:**

| Setting | Development | Production |
|---------|------------|------------|
| Cloud Run min_instances | 0 (scale to zero) | 1 (always warm) |
| Cloud Run max_instances | 5 | 20 |
| Cloud SQL tier | db-f1-micro | db-f1-micro (cost-optimized) |
| Backup retention | 3 snapshots | 7 snapshots |
| Storage lifecycle | 90-day auto-delete | No lifecycle |
| VPC CIDR | 10.9.0.0/28 | 10.8.0.0/28 |
| Apply method | Auto on push to main | Requires `/apply-prod` |

## Security Patterns

- **Workload Identity Federation** for CI/CD (no service account keys)
- **Granular IAM roles** — never use `roles/editor` or `roles/owner`
- **Secret Manager** for all sensitive values (DB URLs, JWT secrets, API keys)
- **VPC Connector** for private Cloud SQL access (no public IP)
- **NAT Gateway** for stable outbound IPs (external API whitelisting)

## CI/CD Workflow

The `terraform.yml` workflow supports:
- **PR comments**: `/plan`, `/plan-dev`, `/plan-prod`, `/apply`, `/apply-dev`, `/apply-prod`
- **Auto-detection**: Changed files determine affected environments
- **Module changes** → runs for BOTH environments
- **Production safety**: Requires explicit `/apply-prod` (never auto-applies)

## Provider

```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}
```

## Common Patterns

### API Enablement
```hcl
resource "google_project_service" "apis" {
  for_each = toset([
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "secretmanager.googleapis.com",
    # ...
  ])
  project = var.project_id
  service = each.value
}
```

### Dynamic Blocks (secrets in Cloud Run)
```hcl
dynamic "env" {
  for_each = var.secrets
  content {
    name = env.value.env_name
    value_source {
      secret_key_ref {
        secret  = env.value.secret_name
        version = "latest"
      }
    }
  }
}
```

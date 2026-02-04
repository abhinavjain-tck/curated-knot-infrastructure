# Development Environment Setup

## Overview

This Terraform configuration manages the `curated-knot-develop` GCP project, which serves as the development/pre-production environment.

## Prerequisites

Before running Terraform, ensure:
1. You have `gcloud` CLI installed and authenticated
2. You have Terraform >= 1.5.0 installed
3. You're authenticated to GCP: `gcloud auth application-default login`

## First-Time Setup

Since Workload Identity Federation is managed by this Terraform config, the first `terraform apply` must be run locally:

```bash
cd environments/development

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply (creates Workload Identity + all infrastructure)
terraform apply
```

After applying, Terraform will output the values needed for GitHub secrets:
- `github_actions_workload_identity_provider` → Use as `GCP_WORKLOAD_IDENTITY_PROVIDER_DEV`
- `github_actions_service_account` → Use as `GCP_SERVICE_ACCOUNT_DEV`

## GitHub Repository Secrets

Add these secrets to the `the-curated-knot` GitHub repository:

| Secret Name | Value Source |
|-------------|--------------|
| `GCP_WORKLOAD_IDENTITY_PROVIDER_DEV` | `terraform output github_actions_workload_identity_provider` |
| `GCP_SERVICE_ACCOUNT_DEV` | `terraform output github_actions_service_account` |

## Infrastructure Resources

This environment creates:

| Resource | Description |
|----------|-------------|
| Workload Identity Pool | GitHub Actions authentication |
| Service Account | `github-actions-dev` for CI/CD |
| Cloud Run | API service (scales to 0 when idle) |
| Cloud SQL | PostgreSQL db-f1-micro |
| VPC Connector | Cloud Run → Cloud SQL connectivity |
| NAT Gateway | Outbound connections (for MongoDB Atlas) |
| Artifact Registry | Docker image storage |
| GCS Bucket | Static assets (90-day lifecycle) |

## Cost Optimization

Development is configured for minimal cost:

- Cloud Run: `min_instances = 0` (scale to zero)
- Cloud Run: `max_instances = 5` (vs 10 in production)
- Cloud SQL: `db-f1-micro` (smallest tier, ~$7/month)
- Cloud SQL: 3 backups retained (vs 7 in production)
- Static assets: Auto-delete after 90 days

**Estimated monthly cost**: ~$60-85/month (when actively used)

## Outputs

After `terraform apply`, get the outputs:

```bash
# All outputs
terraform output

# Specific outputs for GitHub secrets
terraform output github_actions_workload_identity_provider
terraform output github_actions_service_account

# NAT IP for MongoDB Atlas whitelisting
terraform output nat_ips
```

## Importing Existing Resources

If you manually created the GitHub Actions service account before, import it:

```bash
terraform import module.github_actions_workload_identity.google_service_account.github_actions \
  projects/curated-knot-develop/serviceAccounts/github-actions-dev@curated-knot-develop.iam.gserviceaccount.com
```

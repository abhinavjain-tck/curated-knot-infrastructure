# Curated Knot Infrastructure

Terraform configuration for The Curated Knot platform infrastructure on Google Cloud Platform.

## Directory Structure

```
curated-knot-infrastructure/
├── modules/                    # Reusable Terraform modules
│   ├── cloud-run/             # Cloud Run service configuration
│   ├── cloud-sql/             # Cloud SQL PostgreSQL instance
│   ├── networking/            # VPC connector, NAT, Router
│   ├── service-account/       # IAM service accounts
│   ├── storage/               # Cloud Storage buckets
│   └── secrets/               # Secret Manager secrets
├── environments/
│   ├── develop/               # Development environment (curated-knot-prod project)
│   └── production/            # Production environment (curated-knot-production project)
├── scripts/                   # Helper scripts
├── exported/                  # Exported GCP resources (reference only)
└── .github/workflows/         # CI/CD workflows
```

## Environments

| Environment | GCP Project | Branch | URL |
|------------|-------------|--------|-----|
| Develop | curated-knot-prod | develop | develop.thecuratedknot.com |
| Production | curated-knot-production | main | thecuratedknot.com |

## Prerequisites

1. **Terraform** >= 1.5.0
2. **Google Cloud SDK** (gcloud)
3. **GCP Projects** with billing enabled
4. **GCS Buckets** for Terraform state:
   - `curated-knot-develop-tf-state`
   - `curated-knot-production-tf-state`

## Initial Setup

### 1. Create State Buckets

```bash
# Develop environment state bucket
gcloud storage buckets create gs://curated-knot-develop-tf-state \
  --project=curated-knot-prod \
  --location=asia-south1 \
  --uniform-bucket-level-access

# Production environment state bucket
gcloud storage buckets create gs://curated-knot-production-tf-state \
  --project=curated-knot-production \
  --location=asia-south1 \
  --uniform-bucket-level-access
```

### 2. Initialize Terraform

```bash
# For develop environment
cd environments/develop
terraform init

# For production environment
cd environments/production
terraform init
```

### 3. Import Existing Resources (Develop Only)

Since the develop environment uses existing infrastructure, you'll need to import resources:

```bash
cd environments/develop

# Import service accounts
terraform import 'module.api_service_account.google_service_account.account' \
  projects/curated-knot-prod/serviceAccounts/curated-knot-api@curated-knot-prod.iam.gserviceaccount.com

terraform import 'module.github_actions_service_account.google_service_account.account' \
  projects/curated-knot-prod/serviceAccounts/github-actions@curated-knot-prod.iam.gserviceaccount.com

# Import networking
terraform import 'module.networking.google_vpc_access_connector.connector' \
  projects/curated-knot-prod/locations/asia-south1/connectors/vpc-connector

terraform import 'module.networking.google_compute_address.nat_ip[0]' \
  projects/curated-knot-prod/regions/asia-south1/addresses/curated-knot-nat-ip

terraform import 'module.networking.google_compute_router.router[0]' \
  projects/curated-knot-prod/regions/asia-south1/routers/curated-knot-router

terraform import 'module.networking.google_compute_router_nat.nat[0]' \
  curated-knot-prod/asia-south1/curated-knot-router/curated-knot-nat

# Import Cloud SQL
terraform import 'module.cloud_sql.google_sql_database_instance.main' \
  projects/curated-knot-prod/instances/curated-knot-db

# Import Artifact Registry
terraform import 'google_artifact_registry_repository.images' \
  projects/curated-knot-prod/locations/asia-south1/repositories/curated-knot-images

# Import Cloud Run
terraform import 'module.cloud_run_api.google_cloud_run_v2_service.api' \
  projects/curated-knot-prod/locations/asia-south1/services/curated-knot-api

# Import Storage Bucket
terraform import 'module.static_assets.google_storage_bucket.bucket' \
  curated-knot-prod/curated-knot-static-assets
```

### 4. Plan and Apply

```bash
# Always plan first
terraform plan

# Apply changes
terraform apply
```

## GitHub Actions Setup

### Required Secrets

Set these secrets in the GitHub repository settings:

| Secret | Description |
|--------|-------------|
| `WORKLOAD_IDENTITY_PROVIDER` | GCP Workload Identity Provider |
| `TERRAFORM_SERVICE_ACCOUNT` | Service account email for Terraform |

### Workload Identity Federation Setup

```bash
# Create Workload Identity Pool
gcloud iam workload-identity-pools create "github-pool" \
  --project="curated-knot-prod" \
  --location="global" \
  --display-name="GitHub Actions Pool"

# Create OIDC Provider
gcloud iam workload-identity-pools providers create-oidc "github-provider" \
  --project="curated-knot-prod" \
  --location="global" \
  --workload-identity-pool="github-pool" \
  --display-name="GitHub Provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository" \
  --issuer-uri="https://token.actions.githubusercontent.com"

# Allow GitHub repo to impersonate service account
gcloud iam service-accounts add-iam-policy-binding "terraform@curated-knot-prod.iam.gserviceaccount.com" \
  --project="curated-knot-prod" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/attribute.repository/abhinavjain-tck/curated-knot-infrastructure"
```

## Making Changes

1. Create a feature branch from `develop`
2. Make changes to Terraform configurations
3. Open a PR to `develop` - Terraform plan will run automatically
4. After review, merge to `develop` - Terraform apply runs for develop environment
5. When ready for production, open a PR from `develop` to `main`
6. After review, merge to `main` - Terraform apply runs for production

## Module Usage

### Cloud Run

```hcl
module "cloud_run_api" {
  source = "../../modules/cloud-run"

  project_id            = "my-project"
  region                = "asia-south1"
  service_name          = "my-api"
  image                 = "gcr.io/my-project/my-image:tag"
  service_account_email = "sa@my-project.iam.gserviceaccount.com"
  vpc_connector_id      = module.networking.vpc_connector_id
  cloud_sql_connection  = module.cloud_sql.connection_name
  environment           = "production"
  allowed_origins       = "https://example.com"
}
```

### Cloud SQL

```hcl
module "cloud_sql" {
  source = "../../modules/cloud-sql"

  project_id        = "my-project"
  region            = "asia-south1"
  instance_name     = "my-db"
  tier              = "db-f1-micro"
  availability_type = "ZONAL"
}
```

## Troubleshooting

### State Lock Issues

If Terraform state is locked:

```bash
terraform force-unlock LOCK_ID
```

### Import Failures

If import fails, check the resource exists:

```bash
gcloud run services describe curated-knot-api --region=asia-south1 --project=curated-knot-prod
```

### Plan Shows Unexpected Changes

The modules use `lifecycle { ignore_changes }` for fields that change outside Terraform (like image tags). If you see unexpected changes, review the ignore_changes blocks.

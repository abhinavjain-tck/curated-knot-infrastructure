#!/bin/bash
# Script to import existing GCP resources into Terraform state for develop environment
# Run this from the environments/develop directory

set -e

echo "=== Importing existing GCP resources into Terraform state ==="
echo "Project: curated-knot-prod"
echo "Region: asia-south1"
echo ""

# Check if we're in the right directory
if [[ ! -f "main.tf" ]]; then
  echo "Error: Please run this script from the environments/develop directory"
  exit 1
fi

# Initialize Terraform if not already done
echo "Initializing Terraform..."
terraform init

echo ""
echo "=== Importing Service Accounts ==="

echo "Importing API service account..."
terraform import 'module.api_service_account.google_service_account.account' \
  'projects/curated-knot-prod/serviceAccounts/curated-knot-api@curated-knot-prod.iam.gserviceaccount.com' || true

echo "Importing GitHub Actions service account..."
terraform import 'module.github_actions_service_account.google_service_account.account' \
  'projects/curated-knot-prod/serviceAccounts/github-actions@curated-knot-prod.iam.gserviceaccount.com' || true

echo ""
echo "=== Importing Networking ==="

echo "Importing VPC connector..."
terraform import 'module.networking.google_vpc_access_connector.connector' \
  'projects/curated-knot-prod/locations/asia-south1/connectors/vpc-connector' || true

echo "Importing NAT IP..."
terraform import 'module.networking.google_compute_address.nat_ip[0]' \
  'projects/curated-knot-prod/regions/asia-south1/addresses/curated-knot-nat-ip' || true

echo "Importing Cloud Router..."
terraform import 'module.networking.google_compute_router.router[0]' \
  'projects/curated-knot-prod/regions/asia-south1/routers/curated-knot-router' || true

echo "Importing Cloud NAT..."
terraform import 'module.networking.google_compute_router_nat.nat[0]' \
  'curated-knot-prod/asia-south1/curated-knot-router/curated-knot-nat' || true

echo ""
echo "=== Importing Cloud SQL ==="

echo "Importing Cloud SQL instance..."
terraform import 'module.cloud_sql.google_sql_database_instance.main' \
  'projects/curated-knot-prod/instances/curated-knot-db' || true

echo ""
echo "=== Importing Artifact Registry ==="

echo "Importing Artifact Registry repository..."
terraform import 'google_artifact_registry_repository.images' \
  'projects/curated-knot-prod/locations/asia-south1/repositories/curated-knot-images' || true

echo ""
echo "=== Importing Cloud Run ==="

echo "Importing Cloud Run API service..."
terraform import 'module.cloud_run_api.google_cloud_run_v2_service.api' \
  'projects/curated-knot-prod/locations/asia-south1/services/curated-knot-api' || true

echo "Importing Cloud Run IAM binding..."
terraform import 'module.cloud_run_api.google_cloud_run_service_iam_member.public' \
  'projects/curated-knot-prod/locations/asia-south1/services/curated-knot-api roles/run.invoker allUsers' || true

echo ""
echo "=== Importing Storage ==="

echo "Importing static assets bucket..."
terraform import 'module.static_assets.google_storage_bucket.bucket' \
  'curated-knot-prod/curated-knot-static-assets' || true

echo ""
echo "=== Import Complete ==="
echo ""
echo "Run 'terraform plan' to see any differences between the imported state and your configuration."
echo "You may need to adjust the Terraform configuration to match the actual resource state."

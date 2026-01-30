#!/bin/bash
# Import existing production resources into Terraform state
# This script imports resources from curated-knot-prod GCP project

set -e

PROJECT_ID="curated-knot-prod"
REGION="asia-south1"

echo "Importing existing production resources for project: ${PROJECT_ID}"
echo "=================================================="

# Initialize Terraform with new backend
echo "Initializing Terraform..."
terraform init -reconfigure

# Import API Services
echo "Importing API services..."
terraform import 'google_project_service.apis["run.googleapis.com"]' "${PROJECT_ID}/run.googleapis.com" || true
terraform import 'google_project_service.apis["sqladmin.googleapis.com"]' "${PROJECT_ID}/sqladmin.googleapis.com" || true
terraform import 'google_project_service.apis["secretmanager.googleapis.com"]' "${PROJECT_ID}/secretmanager.googleapis.com" || true
terraform import 'google_project_service.apis["vpcaccess.googleapis.com"]' "${PROJECT_ID}/vpcaccess.googleapis.com" || true
terraform import 'google_project_service.apis["artifactregistry.googleapis.com"]' "${PROJECT_ID}/artifactregistry.googleapis.com" || true
terraform import 'google_project_service.apis["cloudbuild.googleapis.com"]' "${PROJECT_ID}/cloudbuild.googleapis.com" || true
terraform import 'google_project_service.apis["iam.googleapis.com"]' "${PROJECT_ID}/iam.googleapis.com" || true
terraform import 'google_project_service.apis["iamcredentials.googleapis.com"]' "${PROJECT_ID}/iamcredentials.googleapis.com" || true

# Import Service Accounts
echo "Importing service accounts..."
terraform import 'module.api_service_account.google_service_account.account' "projects/${PROJECT_ID}/serviceAccounts/curated-knot-api@${PROJECT_ID}.iam.gserviceaccount.com" || true
terraform import 'module.github_actions_service_account.google_service_account.account' "projects/${PROJECT_ID}/serviceAccounts/github-actions@${PROJECT_ID}.iam.gserviceaccount.com" || true

# Import IAM bindings for API service account
echo "Importing API service account IAM bindings..."
terraform import 'module.api_service_account.google_project_iam_member.roles["roles/cloudsql.client"]' "${PROJECT_ID} roles/cloudsql.client serviceAccount:curated-knot-api@${PROJECT_ID}.iam.gserviceaccount.com" || true
terraform import 'module.api_service_account.google_project_iam_member.roles["roles/secretmanager.secretAccessor"]' "${PROJECT_ID} roles/secretmanager.secretAccessor serviceAccount:curated-knot-api@${PROJECT_ID}.iam.gserviceaccount.com" || true
terraform import 'module.api_service_account.google_project_iam_member.roles["roles/logging.logWriter"]' "${PROJECT_ID} roles/logging.logWriter serviceAccount:curated-knot-api@${PROJECT_ID}.iam.gserviceaccount.com" || true
terraform import 'module.api_service_account.google_project_iam_member.roles["roles/cloudtrace.agent"]' "${PROJECT_ID} roles/cloudtrace.agent serviceAccount:curated-knot-api@${PROJECT_ID}.iam.gserviceaccount.com" || true
terraform import 'module.api_service_account.google_project_iam_member.roles["roles/monitoring.metricWriter"]' "${PROJECT_ID} roles/monitoring.metricWriter serviceAccount:curated-knot-api@${PROJECT_ID}.iam.gserviceaccount.com" || true

# Import IAM bindings for GitHub Actions service account
echo "Importing GitHub Actions service account IAM bindings..."
terraform import 'module.github_actions_service_account.google_project_iam_member.roles["roles/run.admin"]' "${PROJECT_ID} roles/run.admin serviceAccount:github-actions@${PROJECT_ID}.iam.gserviceaccount.com" || true
terraform import 'module.github_actions_service_account.google_project_iam_member.roles["roles/iam.serviceAccountUser"]' "${PROJECT_ID} roles/iam.serviceAccountUser serviceAccount:github-actions@${PROJECT_ID}.iam.gserviceaccount.com" || true
terraform import 'module.github_actions_service_account.google_project_iam_member.roles["roles/artifactregistry.writer"]' "${PROJECT_ID} roles/artifactregistry.writer serviceAccount:github-actions@${PROJECT_ID}.iam.gserviceaccount.com" || true
terraform import 'module.github_actions_service_account.google_project_iam_member.roles["roles/storage.admin"]' "${PROJECT_ID} roles/storage.admin serviceAccount:github-actions@${PROJECT_ID}.iam.gserviceaccount.com" || true

# Import Networking resources
echo "Importing networking resources..."
terraform import 'module.networking.google_compute_router.router[0]' "projects/${PROJECT_ID}/regions/${REGION}/routers/curated-knot-router" || true
terraform import 'module.networking.google_vpc_access_connector.connector' "projects/${PROJECT_ID}/locations/${REGION}/connectors/vpc-connector" || true
terraform import 'module.networking.google_compute_address.nat_ip[0]' "projects/${PROJECT_ID}/regions/${REGION}/addresses/curated-knot-nat-ip" || true
terraform import 'module.networking.google_compute_router_nat.nat[0]' "${PROJECT_ID}/${REGION}/curated-knot-router/curated-knot-nat" || true

# Import Cloud SQL
echo "Importing Cloud SQL..."
terraform import 'module.cloud_sql.google_sql_database_instance.main' "${PROJECT_ID}/curated-knot-db" || true

# Import Artifact Registry
echo "Importing Artifact Registry..."
terraform import 'google_artifact_registry_repository.images' "projects/${PROJECT_ID}/locations/${REGION}/repositories/curated-knot-images" || true

# Import Storage Bucket
echo "Importing storage bucket..."
terraform import 'module.static_assets.google_storage_bucket.bucket' "curated-knot-static-assets" || true

# Import Cloud Run Service
echo "Importing Cloud Run service..."
terraform import 'module.cloud_run_api.google_cloud_run_v2_service.api' "projects/${PROJECT_ID}/locations/${REGION}/services/curated-knot-api" || true
terraform import 'module.cloud_run_api.google_cloud_run_service_iam_member.public' "${PROJECT_ID}/locations/${REGION}/services/curated-knot-api roles/run.invoker allUsers" || true

echo "=================================================="
echo "Import complete! Running terraform plan to verify..."
terraform plan

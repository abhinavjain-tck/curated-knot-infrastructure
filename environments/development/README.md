# Development Environment Setup

## GitHub Environment Configuration

To enable Terraform operations for the development environment via GitHub Actions, configure the following GitHub Environment:

### Environment Name
`development`

### Required Secrets

Add these secrets to the `development` environment in the GitHub repository settings:

1. **GCP_PROJECT_ID**
   ```
   curated-knot-develop
   ```

2. **GCP_WORKLOAD_IDENTITY_PROVIDER**
   ```
   projects/543512810080/locations/global/workloadIdentityPools/github-actions-pool/providers/github-provider
   ```

3. **GCP_SERVICE_ACCOUNT**
   ```
   github-actions-dev@curated-knot-develop.iam.gserviceaccount.com
   ```

### Environment Protection Rules

For the development environment:
- **Required reviewers**: None (auto-deploy)
- **Wait timer**: 0 minutes
- **Deployment branches**: `develop` branch only

### How to Configure

1. Go to repository Settings → Environments
2. Click "New environment"
3. Name it `development`
4. Add the three secrets listed above
5. Configure branch protection to allow only `develop` branch

## Infrastructure Resources

This environment creates:
- Cloud Run API service (scales to 0 when idle)
- Cloud SQL PostgreSQL (db-f1-micro, 3 backups)
- VPC Connector for Cloud Run → Cloud SQL
- NAT Gateway for outbound connections
- Artifact Registry for Docker images
- Static assets GCS bucket (with 90-day lifecycle)

## Cost Optimization

- Cloud Run scales to 0 (min_instances = 0)
- Maximum 5 instances (vs 10 in production)
- Smallest Cloud SQL tier (db-f1-micro)
- Only 3 backups retained (vs 7 in production)
- Static assets auto-delete after 90 days

**Estimated monthly cost**: ~$60-85/month (when actively used)

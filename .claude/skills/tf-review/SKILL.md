---
name: tf-review
description: >
  Infrastructure code review for Curated Knot Terraform changes.
  Use when the user asks to review terraform changes, review infrastructure,
  or invokes /tf-review. Checks IAM security, cost optimization,
  environment consistency, module design, and state safety.
disable-model-invocation: true
argument-hint: "[PR number or file path]"
---

# Terraform Review

Review Terraform/infrastructure changes for The Curated Knot GCP setup.

## Workflow

1. **Determine scope**: If `$ARGUMENTS` is a PR number, use `gh pr diff $ARGUMENTS`. If a file path, review that file. Otherwise, use `git diff main...HEAD`.
2. **Analyze changes** against each review dimension.
3. **Output structured review** with risk levels and remediation.

## Review Dimensions

### 1. Security (IAM & Access)

**Critical checks:**
- No `roles/editor` or `roles/owner` — use specific roles
- No service account keys — Workload Identity Federation only
- `allow_unauthenticated` on Cloud Run — must be `false` unless explicitly justified
- No public IP on Cloud SQL — access via VPC connector only
- Secrets in Secret Manager, not inline in Terraform
- No credentials in `.tf` files or tfvars

**IAM roles for service accounts:**
- API service account: Cloud SQL Client, Secret Manager, Logging, Trace, Monitoring
- GitHub Actions: Cloud Run Admin, SA User, Artifact Registry Writer, Storage Admin, Secret Manager Accessor

### 2. Cost Optimization

**Check for:**
- Development resources oversized (should use minimal tiers)
- `min_instances = 0` for dev Cloud Run (scale to zero)
- Storage lifecycle rules on dev buckets (90-day auto-delete)
- Database tier appropriate per environment
- NAT IP count (1 per environment is sufficient)
- Any new resources with cost implications

**Current costs (dev ~$60-85/month):**
- Cloud Run: scales to zero ($0 when idle)
- Cloud SQL: db-f1-micro (~$7/month)
- NAT: ~$30/month
- Storage: minimal

### 3. Environment Consistency

**Check for:**
- Same module version used in both environments
- Same variable interfaces (same variable names, types)
- Appropriate scaling differences (dev lower, prod higher)
- CIDR range conflicts between environments
- Label consistency (`environment`, `managed-by`)

**Compare:**
- `environments/development/main.tf` vs `environments/production/main.tf`
- Module variable interfaces match

### 4. Module Design

**Check for:**
- Variables have `description`
- Default values where sensible
- Proper `type` constraints
- Outputs expose what consumers need
- No hardcoded values that should be variables
- `for_each` over `count` for collections

### 5. Naming Conventions

**Pattern**: `curated-knot-{resource}[-{variant}]`

**Check for:**
- Resources follow naming convention
- Labels applied consistently
- Service account IDs are descriptive

### 6. State Safety

**Check for:**
- `lifecycle.prevent_destroy` on critical resources (databases, state buckets)
- `lifecycle.ignore_changes` where appropriate:
  - Cloud Run image tags: `template[0].containers[0].image`
  - Client version fields
- New resources that may need import before apply
- Resources being replaced that should be updated in-place

### 7. CI/CD Awareness

**Remind about:**
- Module changes affect BOTH environments
- Production requires explicit `/apply-prod`
- Development auto-applies on push to main
- State locks — concurrent applies will conflict

## Output Format

```
## Terraform Review

### 🔴 Critical (Security / Data Loss Risk)
- [Issue with specific file:line]
  Risk: [explanation]
  Fix: [remediation]

### 🟡 Warning (Cost / Consistency)
- [Issue]

### 🔵 Suggestion (Best Practice)
- [Improvement]

### Environment Impact
- Development: [affected / not affected]
- Production: [affected / not affected]
- Apply method: [auto / requires /apply-prod]

### Summary
Blocking issues: N
Recommendation: [approve / request changes]
```

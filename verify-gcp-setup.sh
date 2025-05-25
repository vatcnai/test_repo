#!/bin/bash

# GCP Workload Identity Verification Script
# This script helps diagnose issues with GitHub Actions authentication to GCP

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Get current project
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [[ -z "$PROJECT_ID" ]]; then
    print_error "No project set. Run: gcloud config set project YOUR_PROJECT_ID"
    exit 1
fi

print_status "Checking project: $PROJECT_ID"

# Step 1: Check if required APIs are enabled
print_status "Step 1: Checking required APIs..."
REQUIRED_APIS=(
    "container.googleapis.com"
    "artifactregistry.googleapis.com"
    "iam.googleapis.com"
)

for api in "${REQUIRED_APIS[@]}"; do
    if gcloud services list --enabled --filter="name:$api" --format="value(name)" | grep -q "$api"; then
        print_success "$api is enabled"
    else
        print_error "$api is NOT enabled. Enable it with: gcloud services enable $api"
    fi
done

# Step 2: Check if service account exists
print_status "Step 2: Checking service account..."
SA_EMAIL="github-actions-sa@$PROJECT_ID.iam.gserviceaccount.com"
if gcloud iam service-accounts describe "$SA_EMAIL" &>/dev/null; then
    print_success "Service account exists: $SA_EMAIL"
else
    print_error "Service account does NOT exist: $SA_EMAIL"
    echo "Create it with:"
    echo "gcloud iam service-accounts create github-actions-sa --description='Service account for GitHub Actions CI/CD' --display-name='GitHub Actions Service Account'"
fi

# Step 3: Check workload identity pool
print_status "Step 3: Checking workload identity pool..."
if gcloud iam workload-identity-pools describe github-pool --location=global &>/dev/null; then
    print_success "Workload identity pool 'github-pool' exists"
else
    print_error "Workload identity pool 'github-pool' does NOT exist"
    echo "Create it with:"
    echo "gcloud iam workload-identity-pools create github-pool --location=global --description='Pool for GitHub Actions'"
fi

# Step 4: Check workload identity provider
print_status "Step 4: Checking workload identity provider..."
if gcloud iam workload-identity-pools providers describe github-provider --location=global --workload-identity-pool=github-pool &>/dev/null; then
    print_success "Workload identity provider 'github-provider' exists"
    
    # Show provider details
    print_status "Provider configuration:"
    gcloud iam workload-identity-pools providers describe github-provider \
        --location=global \
        --workload-identity-pool=github-pool \
        --format="yaml(attributeCondition,attributeMapping,oidc)"
else
    print_error "Workload identity provider 'github-provider' does NOT exist"
    echo "You need to create it. First, tell me your GitHub repository (username/repo-name):"
    read -p "GitHub repository: " GITHUB_REPO
    echo ""
    echo "Create it with:"
    echo "gcloud iam workload-identity-pools providers create-oidc github-provider \\"
    echo "    --location=global \\"
    echo "    --workload-identity-pool=github-pool \\"
    echo "    --issuer-uri=https://token.actions.githubusercontent.com \\"
    echo "    --attribute-mapping='google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.actor=assertion.actor' \\"
    echo "    --attribute-condition=\"assertion.repository=='$GITHUB_REPO'\""
fi

# Step 5: Check IAM bindings
print_status "Step 5: Checking IAM policy bindings..."
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')

# Check service account permissions
REQUIRED_ROLES=(
    "roles/artifactregistry.writer"
    "roles/container.developer"
    "roles/container.clusterViewer"
)

for role in "${REQUIRED_ROLES[@]}"; do
    if gcloud projects get-iam-policy $PROJECT_ID --flatten="bindings[].members" --format="table(bindings.role)" --filter="bindings.role:$role AND bindings.members:serviceAccount:$SA_EMAIL" | grep -q "$role"; then
        print_success "Service account has role: $role"
    else
        print_warning "Service account missing role: $role"
        echo "Add it with: gcloud projects add-iam-policy-binding $PROJECT_ID --member='serviceAccount:$SA_EMAIL' --role='$role'"
    fi
done

# Check workload identity binding
print_status "Step 6: Checking workload identity binding..."
if gcloud iam service-accounts get-iam-policy "$SA_EMAIL" --format="value(bindings[].members)" | grep -q "principalSet://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool"; then
    print_success "Workload identity binding exists"
else
    print_error "Workload identity binding does NOT exist"
    echo "You need to create it. First, tell me your GitHub repository (username/repo-name):"
    read -p "GitHub repository: " GITHUB_REPO
    echo ""
    echo "Create it with:"
    echo "gcloud iam service-accounts add-iam-policy-binding $SA_EMAIL \\"
    echo "    --role='roles/iam.workloadIdentityUser' \\"
    echo "    --member='principalSet://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/attribute.repository/$GITHUB_REPO'"
fi

# Step 7: Generate the correct values for GitHub secrets
print_status "Step 7: GitHub Secrets Values"
echo ""
echo "=== COPY THESE VALUES TO YOUR GITHUB SECRETS ==="
echo ""
echo "GCP_PROJECT_ID:"
echo "$PROJECT_ID"
echo ""
echo "GCP_WORKLOAD_IDENTITY_PROVIDER:"
echo "projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/providers/github-provider"
echo ""
echo "GCP_SERVICE_ACCOUNT:"
echo "$SA_EMAIL"
echo ""
echo "================================================="

print_status "Verification complete!"
print_warning "If any items above show errors, fix them before running your GitHub Actions workflow." 
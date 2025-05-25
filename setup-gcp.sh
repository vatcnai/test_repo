#!/bin/bash

# GCP Setup Script for GitHub Actions CI/CD Pipeline
# This script automates the setup process described in TUTORIAL.md

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
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

# Check if required tools are installed
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    if ! command -v gcloud &> /dev/null; then
        print_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed. Please install it first."
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Get user inputs
get_user_inputs() {
    print_status "Getting user inputs..."
    
    # Get GitHub repository
    read -p "Enter your GitHub repository (format: username/repo-name): " GITHUB_REPO
    if [[ ! $GITHUB_REPO =~ ^[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+$ ]]; then
        print_error "Invalid repository format. Use: username/repo-name"
        exit 1
    fi
    
    # Get project ID
    read -p "Enter your GCP project ID: " PROJECT_ID
    if [[ -z "$PROJECT_ID" ]]; then
        print_error "Project ID cannot be empty"
        exit 1
    fi
    
    # Get region/zone preferences
    read -p "Enter preferred region (default: us-central1): " REGION
    REGION=${REGION:-us-central1}
    
    read -p "Enter preferred zone (default: us-central1-a): " ZONE
    ZONE=${ZONE:-us-central1-a}
    
    print_success "User inputs collected"
}

# Set up GCP project
setup_project() {
    print_status "Setting up GCP project..."
    
    # Set the project
    gcloud config set project $PROJECT_ID
    
    # Enable required APIs
    print_status "Enabling required APIs..."
    gcloud services enable container.googleapis.com
    gcloud services enable artifactregistry.googleapis.com
    gcloud services enable cloudbuild.googleapis.com
    gcloud services enable iam.googleapis.com
    
    print_success "GCP project setup completed"
}

# Create Artifact Registry repository
create_artifact_registry() {
    print_status "Creating Artifact Registry repository..."
    
    gcloud artifacts repositories create my-docker-repo \
        --repository-format=docker \
        --location=$REGION \
        --description="Docker repository for CI/CD pipeline"
    
    print_success "Artifact Registry repository created"
}

# Create GKE cluster
create_gke_cluster() {
    print_status "Creating GKE cluster (this may take several minutes)..."
    
    gcloud container clusters create my-gke-cluster \
        --zone=$ZONE \
        --num-nodes=2 \
        --machine-type=e2-medium \
        --enable-autorepair \
        --enable-autoupgrade \
        --workload-pool=$PROJECT_ID.svc.id.goog
    
    print_success "GKE cluster created"
}

# Create service account
create_service_account() {
    print_status "Creating service account..."
    
    gcloud iam service-accounts create github-actions-sa \
        --description="Service account for GitHub Actions CI/CD" \
        --display-name="GitHub Actions Service Account"
    
    print_success "Service account created"
}

# Grant permissions
grant_permissions() {
    print_status "Granting permissions to service account..."
    
    # Grant permissions to push to Artifact Registry
    gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:github-actions-sa@$PROJECT_ID.iam.gserviceaccount.com" \
        --role="roles/artifactregistry.writer"
    
    # Grant permissions to deploy to GKE
    gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:github-actions-sa@$PROJECT_ID.iam.gserviceaccount.com" \
        --role="roles/container.developer"
    
    # Grant permission to get GKE credentials
    gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:github-actions-sa@$PROJECT_ID.iam.gserviceaccount.com" \
        --role="roles/container.clusterViewer"
    
    print_success "Permissions granted"
}

# Setup Workload Identity
setup_workload_identity() {
    print_status "Setting up Workload Identity Federation..."
    
    # Create workload identity pool
    gcloud iam workload-identity-pools create github-pool \
        --location="global" \
        --description="Pool for GitHub Actions"
    
    # Create workload identity provider
    gcloud iam workload-identity-pools providers create-oidc github-provider \
        --location="global" \
        --workload-identity-pool="github-pool" \
        --issuer-uri="https://token.actions.githubusercontent.com" \
        --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.actor=assertion.actor" \
        --attribute-condition="assertion.repository=='$GITHUB_REPO'"
    
    # Get project number
    PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')
    
    # Bind service account to workload identity
    gcloud iam service-accounts add-iam-policy-binding \
        github-actions-sa@$PROJECT_ID.iam.gserviceaccount.com \
        --role="roles/iam.workloadIdentityUser" \
        --member="principalSet://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/attribute.repository/$GITHUB_REPO"
    
    print_success "Workload Identity Federation setup completed"
}

# Display final information
display_final_info() {
    print_success "Setup completed! Here are your GitHub secrets:"
    echo ""
    echo "Add these secrets to your GitHub repository:"
    echo "Repository: https://github.com/$GITHUB_REPO/settings/secrets/actions"
    echo ""
    echo "GCP_PROJECT_ID:"
    echo "$PROJECT_ID"
    echo ""
    echo "GCP_WORKLOAD_IDENTITY_PROVIDER:"
    PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')
    echo "projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/providers/github-provider"
    echo ""
    echo "GCP_SERVICE_ACCOUNT:"
    echo "github-actions-sa@$PROJECT_ID.iam.gserviceaccount.com"
    echo ""
    print_warning "Don't forget to:"
    echo "1. Update the workflow file with your project ID"
    echo "2. Deploy the initial Kubernetes resources: kubectl apply -f k8s-deployment.yaml"
    echo "3. Update the image reference in k8s-deployment.yaml with your project ID"
}

# Main execution
main() {
    echo "==================================="
    echo "GCP CI/CD Pipeline Setup Script"
    echo "==================================="
    echo ""
    
    check_prerequisites
    get_user_inputs
    
    print_warning "This script will create resources in GCP that may incur charges."
    read -p "Do you want to continue? (y/N): " CONFIRM
    if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
        print_status "Setup cancelled"
        exit 0
    fi
    
    setup_project
    create_artifact_registry
    create_gke_cluster
    create_service_account
    grant_permissions
    setup_workload_identity
    display_final_info
    
    print_success "All done! Check the output above for your GitHub secrets."
}

# Run main function
main "$@" 
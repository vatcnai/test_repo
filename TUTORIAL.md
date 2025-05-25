# Complete Tutorial: GitHub Actions CI/CD Pipeline for Google Cloud Platform

This tutorial will walk you through creating a complete CI/CD pipeline that builds a Docker container, pushes it to Google Cloud Artifact Registry, and deploys it to Google Kubernetes Engine (GKE).

## Table of Contents

1. [Prerequisites and Setup](#prerequisites-and-setup)
2. [Google Cloud Platform Setup](#google-cloud-platform-setup)
3. [Workload Identity Federation Setup](#workload-identity-federation-setup)
4. [GitHub Repository Setup](#github-repository-setup)
5. [Understanding the Workflow](#understanding-the-workflow)
6. [Testing and Deployment](#testing-and-deployment)

## Prerequisites and Setup

### What You'll Need

- A Google Cloud Platform account with billing enabled
- A GitHub repository
- Basic knowledge of Docker, Kubernetes, and CI/CD concepts
- `gcloud` CLI installed locally (optional, for testing)

### Why These Prerequisites Matter

- **GCP Account with Billing**: Required because we'll use paid services like GKE and Artifact Registry
- **GitHub Repository**: Where our code and workflow will live
- **Docker/K8s Knowledge**: Helps understand what the pipeline is doing
- **gcloud CLI**: Useful for local testing and troubleshooting

## Google Cloud Platform Setup

### Step 1: Create a New GCP Project

1. **Go to the Google Cloud Console**: https://console.cloud.google.com/
2. **Click "Select a project" → "New Project"**
3. **Enter project details**:
   - Project name: `my-cicd-project` (or your preferred name)
   - Project ID: Will be auto-generated, note this down as `my-project-id`
4. **Click "Create"**

**Why**: Each GCP project is an isolated environment with its own resources, billing, and permissions. This keeps your CI/CD setup separate from other projects.

### Step 2: Enable Required APIs

Run these commands in Cloud Shell or with gcloud CLI:

```bash
# Enable required APIs
gcloud services enable container.googleapis.com
gcloud services enable artifactregistry.googleapis.com
gcloud services enable cloudbuild.googleapis.com
gcloud services enable iam.googleapis.com
```

**What each API does**:

- `container.googleapis.com`: Google Kubernetes Engine (GKE)
- `artifactregistry.googleapis.com`: Docker image storage
- `cloudbuild.googleapis.com`: Build services (optional, but useful)
- `iam.googleapis.com`: Identity and Access Management

### Step 3: Create Artifact Registry Repository

```bash
# Create a Docker repository in Artifact Registry
gcloud artifacts repositories create my-docker-repo \
    --repository-format=docker \
    --location=us-central1 \
    --description="Docker repository for CI/CD pipeline"
```

**Why Artifact Registry**:

- Secure, private Docker image storage
- Integrated with GCP IAM for access control
- Better performance than Docker Hub for GCP deployments
- Vulnerability scanning capabilities

### Step 4: Create GKE Cluster

```bash
# Create a GKE cluster
gcloud container clusters create my-gke-cluster \
    --zone=us-central1-a \
    --num-nodes=2 \
    --machine-type=e2-medium \
    --enable-autorepair \
    --enable-autoupgrade \
    --workload-pool=my-project-id.svc.id.goog
```

**Key parameters explained**:

- `--workload-pool`: Enables Workload Identity (crucial for secure authentication)
- `--enable-autorepair`: Automatically repairs unhealthy nodes
- `--enable-autoupgrade`: Keeps cluster updated with security patches
- `--machine-type=e2-medium`: Cost-effective machine type for testing

## Workload Identity Federation Setup

This is the most complex but crucial part. Workload Identity Federation allows GitHub Actions to authenticate to GCP without storing long-lived service account keys.

### Step 5: Create Service Account

```bash
# Create service account for GitHub Actions
gcloud iam service-accounts create github-actions-sa \
    --description="Service account for GitHub Actions CI/CD" \
    --display-name="GitHub Actions Service Account"
```

### Step 6: Grant Necessary Permissions

```bash
# Get your project ID
PROJECT_ID=$(gcloud config get-value project)

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
```

**Why these specific roles**:

- `artifactregistry.writer`: Push Docker images to registry
- `container.developer`: Deploy to GKE clusters
- `container.clusterViewer`: Get cluster credentials

### Step 7: Create Workload Identity Pool

```bash
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
    --attribute-condition="assertion.repository=='YOUR_GITHUB_USERNAME/YOUR_REPO_NAME'"
```

**Replace `YOUR_GITHUB_USERNAME/YOUR_REPO_NAME`** with your actual GitHub repository (e.g., `john-doe/my-app`).

**What this does**:

- Creates a secure way for GitHub to authenticate to GCP
- Maps GitHub token claims to Google Cloud attributes
- Restricts access to only your specific repository

### Step 8: Bind Service Account to Workload Identity

```bash
# Allow GitHub Actions to impersonate the service account
gcloud iam service-accounts add-iam-policy-binding \
    github-actions-sa@$PROJECT_ID.iam.gserviceaccount.com \
    --role="roles/iam.workloadIdentityUser" \
    --member="principalSet://iam.googleapis.com/projects/$(gcloud projects describe $PROJECT_ID --format='value(projectNumber)')/locations/global/workloadIdentityPools/github-pool/attribute.repository/YOUR_GITHUB_USERNAME/YOUR_REPO_NAME"
```

### Step 9: Get Required Values for GitHub Secrets

```bash
# Get project ID
echo "Project ID: $(gcloud config get-value project)"

# Get project number
echo "Project Number: $(gcloud projects describe $(gcloud config get-value project) --format='value(projectNumber)')"

# Get workload identity provider
echo "Workload Identity Provider: projects/$(gcloud projects describe $(gcloud config get-value project) --format='value(projectNumber)')/locations/global/workloadIdentityPools/github-pool/providers/github-provider"

# Get service account email
echo "Service Account: github-actions-sa@$(gcloud config get-value project).iam.gserviceaccount.com"
```

**Save these values** - you'll need them for GitHub secrets.

## GitHub Repository Setup

### Step 10: Configure GitHub Secrets

Go to your GitHub repository → Settings → Secrets and variables → Actions

Add these secrets:

1. **`GCP_PROJECT_ID`**: Your GCP project ID (from step 9)
2. **`GCP_WORKLOAD_IDENTITY_PROVIDER`**: The workload identity provider URL (from step 9)
3. **`GCP_SERVICE_ACCOUNT`**: The service account email (from step 9)

**Why secrets**: These values are sensitive and shouldn't be hardcoded in your workflow files.

### Step 11: Update Workflow File

Update the workflow file (`.github/workflows/deploy-to-gcp.yml`) with your specific values:

```yaml
env:
  REGISTRY_GCP: us-central1-docker.pkg.dev/YOUR_PROJECT_ID # Replace with your project ID
  REPOSITORY_GCP: my-docker-repo # Must match the repo you created
  IMAGE_NAME: my-app
  IMAGE_TAG: latest
```

## Understanding the Workflow

Let's break down each part of the workflow and understand what it does:

### Workflow Trigger

```yaml
on:
  push:
    branches:
      - main
```

**What**: Triggers the workflow when code is pushed to the main branch
**Why**: Ensures every change to main is automatically deployed

### Permissions

```yaml
permissions:
  contents: "read"
  id-token: "write"
  packages: "read"
```

**What**: Grants specific permissions to the GitHub Actions runner
**Why**:

- `id-token: write`: Required for Workload Identity Federation
- `contents: read`: Allows checking out the repository
- `packages: read`: Allows reading from GitHub packages (if needed)

### Build and Push Job

#### Checkout Code

```yaml
- name: Checkout the repo
  uses: actions/checkout@v4
```

**What**: Downloads your repository code to the runner
**Why**: The runner needs your code to build the Docker image

#### Set up Node.js

```yaml
- name: Set up Node.js
  uses: actions/setup-node@v4
  with:
    node-version: "20"
    cache: "npm"
```

**What**: Installs Node.js and caches npm dependencies
**Why**: Your application needs Node.js to run, and caching speeds up builds

#### Install Dependencies and Build

```yaml
- name: Install dependencies
  run: npm ci

- name: Build application
  run: npm run build
```

**What**: Installs exact dependencies and builds the application
**Why**: `npm ci` is faster and more reliable than `npm install` for CI/CD

#### Docker Build with Secrets

```yaml
- name: Create env file for Docker secrets
  run: |
    touch .env.docker
    echo "NODE_ENV=production" > .env.docker

- name: Build Docker image
  run: |
    DOCKER_BUILDKIT=1 docker build \
      -t ${{ env.REPOSITORY_GCP }}/${{ env.IMAGE_NAME }} \
      --secret id=env,src=.env.docker \
      .
```

**What**: Creates a temporary env file and builds Docker image with secrets
**Why**:

- Docker secrets allow secure passing of sensitive data during build
- `DOCKER_BUILDKIT=1` enables advanced Docker features
- Temporary file is cleaned up after build

#### Google Cloud Authentication

```yaml
- name: Authenticate to Google Cloud
  uses: google-github-actions/auth@v2
  with:
    project_id: ${{ secrets.GCP_PROJECT_ID }}
    workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
    service_account: ${{ secrets.GCP_SERVICE_ACCOUNT }}
```

**What**: Authenticates GitHub Actions to Google Cloud using Workload Identity
**Why**: Secure authentication without storing service account keys

#### Configure Docker and Push

```yaml
- name: Configure Docker for Artifact Registry
  run: gcloud auth configure-docker us-central1-docker.pkg.dev

- name: Tag image for Google Cloud
  run: |
    docker tag ${{ env.REPOSITORY_GCP }}/${{ env.IMAGE_NAME }} \
      ${{ env.REGISTRY_GCP }}/${{ env.REPOSITORY_GCP }}/${{ env.IMAGE_NAME }}:${{ env.IMAGE_TAG }}

- name: Push image to Artifact Registry
  run: |
    docker push ${{ env.REGISTRY_GCP }}/${{ env.REPOSITORY_GCP }}/${{ env.IMAGE_NAME }}:${{ env.IMAGE_TAG }}
```

**What**: Configures Docker authentication, tags image with full registry path, and pushes
**Why**:

- Docker needs authentication to push to private registries
- Proper tagging ensures the image can be found by Kubernetes
- Pushing makes the image available for deployment

### Deploy Job

#### Job Dependencies

```yaml
deploy:
  runs-on: ubuntu-22.04
  needs: [build_and_push_gcp]
```

**What**: This job only runs after the build job completes successfully
**Why**: Can't deploy an image that doesn't exist or failed to build

#### Get GKE Credentials

```yaml
- name: Get GKE credentials
  uses: google-github-actions/get-gke-credentials@v2
  with:
    cluster_name: ${{ env.CLUSTER_NAME }}
    location: ${{ env.CLUSTER_ZONE }}
```

**What**: Downloads Kubernetes configuration to connect to your GKE cluster
**Why**: kubectl needs cluster credentials to deploy applications

#### Deploy to Kubernetes

```yaml
- name: Deploy to GKE
  run: |
    kubectl set image deployment/my-app-deployment \
      my-app=${{ env.REGISTRY_GCP }}/${{ env.REPOSITORY_GCP }}/${{ env.IMAGE_NAME }}:${{ env.IMAGE_TAG }} \
      -n default
    kubectl rollout status deployment/my-app-deployment -n default
```

**What**: Updates the deployment with the new image and waits for rollout to complete
**Why**:

- `kubectl set image` triggers a rolling update
- `kubectl rollout status` ensures the deployment succeeded before marking the job complete

## Testing and Deployment

### Step 12: Deploy Initial Kubernetes Resources

Before the first workflow run, deploy the Kubernetes resources:

```bash
# Get GKE credentials locally
gcloud container clusters get-credentials my-gke-cluster --zone=us-central1-a

# Apply the Kubernetes deployment
kubectl apply -f k8s-deployment.yaml
```

### Step 13: Test the Workflow

1. **Make a change to your code** (e.g., update the message in `server.js`)
2. **Commit and push to main branch**:
   ```bash
   git add .
   git commit -m "Test CI/CD pipeline"
   git push origin main
   ```
3. **Watch the workflow** in GitHub Actions tab
4. **Check deployment status**:
   ```bash
   kubectl get deployments
   kubectl get pods
   kubectl get services
   ```

### Step 14: Access Your Application

```bash
# Get the external IP of your service
kubectl get service my-app-service

# Once you have the external IP, visit:
# http://EXTERNAL_IP/
```

## Troubleshooting Common Issues

### Authentication Errors

- **Issue**: "Permission denied" errors
- **Solution**: Verify service account permissions and workload identity setup
- **Check**: Ensure the repository name in workload identity condition matches exactly

### Image Pull Errors

- **Issue**: "ImagePullBackOff" in Kubernetes
- **Solution**: Verify image name and tag in deployment match what was pushed
- **Check**: Ensure GKE has permission to pull from Artifact Registry

### Build Failures

- **Issue**: Docker build fails
- **Solution**: Check Dockerfile syntax and ensure all files exist
- **Check**: Verify Node.js version compatibility

### Deployment Timeouts

- **Issue**: Deployment doesn't complete
- **Solution**: Check pod logs with `kubectl logs deployment/my-app-deployment`
- **Check**: Verify health check endpoints are working

## Security Best Practices

1. **Use Workload Identity**: Never store service account keys in GitHub secrets
2. **Least Privilege**: Only grant minimum required permissions
3. **Repository Restrictions**: Limit workload identity to specific repositories
4. **Regular Updates**: Keep GitHub Actions and base images updated
5. **Secrets Management**: Use GitHub secrets for all sensitive data

## Cost Optimization

1. **Use Autopilot GKE**: Consider GKE Autopilot for automatic resource optimization
2. **Right-size Resources**: Set appropriate CPU/memory requests and limits
3. **Clean up**: Delete unused images from Artifact Registry
4. **Monitoring**: Set up billing alerts to avoid unexpected costs

## Next Steps

1. **Add Testing**: Include unit tests, integration tests, and security scans
2. **Multi-environment**: Set up staging and production environments
3. **Monitoring**: Add application monitoring and logging
4. **Rollback Strategy**: Implement automated rollback on deployment failures
5. **Infrastructure as Code**: Use Terraform or similar tools for infrastructure management

This tutorial provides a complete, production-ready CI/CD pipeline that follows security best practices and can be extended for more complex applications.

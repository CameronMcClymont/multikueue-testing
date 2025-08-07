#!/bin/bash

# MultiKueue Local Setup Script
# Sets up two Kubernetes clusters (manager and worker) using Colima and k3d
# Author: Claude Code
# Date: 2025-08-07

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
COLIMA_PROFILE="multikueue"
MANAGER_CLUSTER="manager"
WORKER_CLUSTER="worker"
KUEUE_VERSION="v0.13.1"  # Latest as of August 2025

echo -e "${BLUE}🚀 Setting up MultiKueue local environment${NC}"
echo "=================================="

# Function to print status
print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to run commands with visible output
run_cmd() {
    echo -e "${YELLOW}$ $*${NC}"
    "$@"
}

# Check prerequisites
echo -e "${BLUE}📋 Checking prerequisites...${NC}"

# Check if Homebrew is installed
if ! command -v brew &> /dev/null; then
    print_error "Homebrew is not installed. Please install it first: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    exit 1
fi
print_status "Homebrew is installed"

# Install required tools
echo -e "${BLUE}🔧 Installing required tools...${NC}"

tools=("colima" "kubectl" "k3d" "helm")
for tool in "${tools[@]}"; do
    if ! command -v "$tool" &> /dev/null; then
        echo "Installing $tool..."
        run_cmd brew install "$tool"
        print_status "$tool installed"
    else
        print_status "$tool already installed"
    fi
done

# Delete any existing multikueue Colima profile for a clean start
echo -e "${BLUE}🗑️  Deleting any existing multikueue Colima profile...${NC}"
run_cmd colima delete --profile $COLIMA_PROFILE --force 2>/dev/null || true
print_status "Existing multikueue Colima profile deleted"

# Start Colima with adequate resources
echo -e "${BLUE}🐋 Starting Colima with profile: $COLIMA_PROFILE${NC}"
run_cmd colima start --profile $COLIMA_PROFILE \
    --cpu 4 \
    --memory 8 \
    --disk 50 \
    --network-address \
    --kubernetes=false \
    --runtime docker

print_status "Colima started with profile: $COLIMA_PROFILE"

# Wait for Colima to be ready
echo "Waiting for Colima to be ready..."
sleep 10

# Create a shared Docker network for k3d clusters
echo -e "${BLUE}🌐 Creating shared Docker network for clusters...${NC}"
run_cmd docker network create multikueue-network 2>/dev/null || echo "Network already exists"

# Create manager cluster
echo -e "${BLUE}🏗️  Creating manager cluster: $MANAGER_CLUSTER${NC}"
run_cmd k3d cluster create $MANAGER_CLUSTER \
    --agents 1 \
    --servers 1 \
    --port "6443:6443@server:0" \
    --port "80:80@loadbalancer" \
    --port "443:443@loadbalancer" \
    --k3s-arg "--disable=traefik@server:0" \
    --network multikueue-network \
    --wait

print_status "Manager cluster '$MANAGER_CLUSTER' created"

# Create worker cluster
echo -e "${BLUE}🏗️  Creating worker cluster: $WORKER_CLUSTER${NC}"
run_cmd k3d cluster create $WORKER_CLUSTER \
    --agents 1 \
    --servers 1 \
    --port "6444:6443@server:0" \
    --port "8080:80@loadbalancer" \
    --port "8443:443@loadbalancer" \
    --k3s-arg "--disable=traefik@server:0" \
    --network multikueue-network \
    --wait

print_status "Worker cluster '$WORKER_CLUSTER' created"

# Verify clusters
echo -e "${BLUE}🔍 Verifying cluster contexts...${NC}"
run_cmd kubectl config get-contexts

# Switch to manager cluster and install Kueue
echo -e "${BLUE}📦 Installing Kueue on manager cluster...${NC}"
run_cmd kubectl config use-context k3d-$MANAGER_CLUSTER
run_cmd kubectl apply --server-side -f https://github.com/kubernetes-sigs/kueue/releases/download/$KUEUE_VERSION/manifests.yaml

print_status "Kueue installed on manager cluster"

# Switch to worker cluster and install Kueue
echo -e "${BLUE}📦 Installing Kueue on worker cluster...${NC}"
run_cmd kubectl config use-context k3d-$WORKER_CLUSTER
run_cmd kubectl apply --server-side -f https://github.com/kubernetes-sigs/kueue/releases/download/$KUEUE_VERSION/manifests.yaml

print_status "Kueue installed on worker cluster"

# Wait for Kueue to be ready on both clusters
echo -e "${BLUE}⏳ Waiting for Kueue components to be ready...${NC}"

# Manager cluster
run_cmd kubectl config use-context k3d-$MANAGER_CLUSTER
echo "Waiting for Kueue components in manager cluster..."
run_cmd kubectl wait --for=condition=available --timeout=300s deployment/kueue-controller-manager -n kueue-system

# Worker cluster
run_cmd kubectl config use-context k3d-$WORKER_CLUSTER
echo "Waiting for Kueue components in worker cluster..."
run_cmd kubectl wait --for=condition=available --timeout=300s deployment/kueue-controller-manager -n kueue-system

print_status "Kueue components are ready on both clusters"

# Configure Kueue to work with minimal workload types only
echo -e "${BLUE}⚙️  Configuring Kueue for minimal workload types...${NC}"

# Create ConfigMap to disable external integrations validation
run_cmd kubectl config use-context k3d-$MANAGER_CLUSTER
echo -e "${YELLOW}$ kubectl create configmap kueue-manager-config -n kueue-system --from-literal=controller_manager_config.yaml='<YAML_CONFIG>' --dry-run=client -o yaml | kubectl apply -f -${NC}"
kubectl create configmap kueue-manager-config -n kueue-system --from-literal=controller_manager_config.yaml='
apiVersion: config.kueue.x-k8s.io/v1beta1
kind: Configuration
namespace: kueue-system
health:
  healthProbeBindAddress: :8081
metrics:
  bindAddress: :8080
webhook:
  port: 9443
leaderElection:
  leaderElect: true
  resourceName: c1f6bfd2.kueue.x-k8s.io
controller:
  groupKindConcurrency:
    Job.batch: 5
    Pod.v1: 5
    Workload.kueue.x-k8s.io: 5
    LocalQueue.kueue.x-k8s.io: 1
    ClusterQueue.kueue.x-k8s.io: 1
    ResourceFlavor.kueue.x-k8s.io: 1
integrations:
  frameworks:
    - "batch/job"
  podOptions:
    namespaceSelector:
      matchExpressions:
      - key: kubernetes.io/metadata.name
        operator: NotIn
        values: [ kube-system, kueue-system ]
' --dry-run=client -o yaml | kubectl apply -f -

# Do the same for worker cluster
run_cmd kubectl config use-context k3d-$WORKER_CLUSTER
echo -e "${YELLOW}$ kubectl create configmap kueue-manager-config -n kueue-system --from-literal=controller_manager_config.yaml='<YAML_CONFIG>' --dry-run=client -o yaml | kubectl apply -f -${NC}"
kubectl create configmap kueue-manager-config -n kueue-system --from-literal=controller_manager_config.yaml='
apiVersion: config.kueue.x-k8s.io/v1beta1
kind: Configuration
namespace: kueue-system
health:
  healthProbeBindAddress: :8081
metrics:
  bindAddress: :8080
webhook:
  port: 9443
leaderElection:
  leaderElect: true
  resourceName: c1f6bfd2.kueue.x-k8s.io
controller:
  groupKindConcurrency:
    Job.batch: 5
    Pod.v1: 5
    Workload.kueue.x-k8s.io: 5
    LocalQueue.kueue.x-k8s.io: 1
    ClusterQueue.kueue.x-k8s.io: 1
    ResourceFlavor.kueue.x-k8s.io: 1
integrations:
  frameworks:
    - "batch/job"
  podOptions:
    namespaceSelector:
      matchExpressions:
      - key: kubernetes.io/metadata.name
        operator: NotIn
        values: [ kube-system, kueue-system ]
' --dry-run=client -o yaml | kubectl apply -f -

# Restart Kueue controllers to pick up the new config
run_cmd kubectl config use-context k3d-$MANAGER_CLUSTER
run_cmd kubectl rollout restart deployment/kueue-controller-manager -n kueue-system

run_cmd kubectl config use-context k3d-$WORKER_CLUSTER
run_cmd kubectl rollout restart deployment/kueue-controller-manager -n kueue-system

print_status "Kueue configured for minimal workload types (Jobs only)"

echo ""
echo -e "${GREEN}🎉 Setup completed successfully!${NC}"
echo ""
echo "Next steps:"
echo "1. Run './2-configure-multikueue.sh' to configure MultiKueue"
echo "2. Test the setup with sample jobs"
echo ""
echo "Cluster information:"
echo "- Manager cluster: k3d-$MANAGER_CLUSTER (port 6443)"
echo "- Worker cluster: k3d-$WORKER_CLUSTER (port 6444)"
echo ""
echo "To switch between clusters:"
echo "- kubectl config use-context k3d-$MANAGER_CLUSTER"
echo "- kubectl config use-context k3d-$WORKER_CLUSTER"
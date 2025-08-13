#!/bin/bash

# MultiKueue Worker Cluster Setup Script
# Sets up the worker Kubernetes cluster using k3d
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
COLIMA_PROFILE="multikueue-worker"
WORKER_CLUSTER="worker"
KUEUE_VERSION="v0.13.1"  # Latest as of August 2025

echo -e "${BLUE}🚀 Setting up MultiKueue Worker Cluster${NC}"
echo "======================================"

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

# Install required tools if not available
tools=("colima" "kubectl" "k3d")
for tool in "${tools[@]}"; do
    if ! command -v "$tool" &> /dev/null; then
        echo "Installing $tool..."
        run_cmd brew install "$tool"
        print_status "$tool installed"
    else
        print_status "$tool already installed"
    fi
done

# Delete any existing worker Colima profile for a clean start
echo -e "${BLUE}🗑️  Deleting any existing worker Colima profile...${NC}"
run_cmd colima delete --profile $COLIMA_PROFILE --force 2>/dev/null || true
print_status "Existing worker Colima profile deleted"

# Start Colima with adequate resources and network access
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

# Create worker cluster with external port mapping for cross-VM access
echo -e "${BLUE}🏗️  Creating worker cluster: $WORKER_CLUSTER${NC}"
run_cmd k3d cluster create $WORKER_CLUSTER \
    --agents 1 \
    --servers 1 \
    --port "6444:6443@server:0" \
    --port "8080:80@loadbalancer" \
    --port "8443:443@loadbalancer" \
    --k3s-arg "--disable=traefik@server:0" \
    --wait

print_status "Worker cluster '$WORKER_CLUSTER' created"

# Verify cluster
echo -e "${BLUE}🔍 Verifying worker cluster context...${NC}"
run_cmd kubectl config use-context k3d-$WORKER_CLUSTER
run_cmd kubectl get nodes

# Install Kueue on worker cluster
echo -e "${BLUE}📦 Installing Kueue on worker cluster...${NC}"
run_cmd kubectl apply --server-side -f https://github.com/kubernetes-sigs/kueue/releases/download/$KUEUE_VERSION/manifests.yaml

print_status "Kueue installed on worker cluster"

# Wait for Kueue to be ready
echo -e "${BLUE}⏳ Waiting for Kueue components to be ready...${NC}"
echo "Waiting for Kueue components in worker cluster..."
run_cmd kubectl wait --for=condition=available --timeout=300s deployment/kueue-controller-manager -n kueue-system

print_status "Kueue components are ready on worker cluster"

# Configure Kueue to work with minimal workload types only
echo -e "${BLUE}⚙️  Configuring Kueue for minimal workload types...${NC}"

# Create ConfigMap to disable external integrations validation
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

# Restart Kueue controller to pick up the new config
run_cmd kubectl rollout restart deployment/kueue-controller-manager -n kueue-system

print_status "Kueue configured for minimal workload types (Jobs only)"

echo ""
echo -e "${GREEN}🎉 Worker cluster setup completed successfully!${NC}"
echo ""
echo "Worker cluster information:"
echo "- Cluster name: k3d-$WORKER_CLUSTER"
echo "- Colima VM profile: $COLIMA_PROFILE"
echo "- API server: localhost:6443 (within worker VM)"
echo "- API server (external): localhost:6444 (accessible from host/other VMs)"
echo "- LoadBalancer ports: 8080/8443"
echo ""
echo "To check the cluster:"
echo "- kubectl config use-context k3d-$WORKER_CLUSTER"
echo "- kubectl get pods -n kueue-system"
echo ""
echo "Available clusters:"
run_cmd kubectl config get-contexts
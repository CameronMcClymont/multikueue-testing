#!/bin/bash

# MultiKueue Worker Configuration Script
# Configures MultiKueue resources on the worker cluster
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
WORKER_CLUSTER="worker"

echo -e "${BLUE}⚙️  Configuring MultiKueue on Worker Cluster${NC}"
echo "==========================================="

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

# Check if worker cluster exists
if ! kubectl config get-contexts | grep -q "k3d-$WORKER_CLUSTER"; then
    print_error "Worker cluster 'k3d-$WORKER_CLUSTER' not found. Please run './2-setup-worker-cluster.sh' first."
    exit 1
fi

print_status "Worker cluster is available"

# Step 1: Configure Worker Cluster
echo -e "${BLUE}🔧 Step 1: Configuring worker cluster...${NC}"

# Switch to worker cluster context (should already be available from previous setup)
echo "Switching to worker cluster context"
run_cmd kubectl config use-context k3d-$WORKER_CLUSTER

# Apply worker cluster manifests
echo "Applying worker cluster manifests..."
run_cmd kubectl apply -f worker-cluster-manifests.yaml

# Verify worker cluster resources are created
echo "Verifying worker cluster resources..."
sleep 3

kubectl get clusterqueue/worker-cluster-queue -n kueue-system --no-headers >/dev/null
kubectl get localqueue/manager-local-queue -n multikueue-demo --no-headers >/dev/null
kubectl get localqueue/default-local-queue -n default --no-headers >/dev/null
echo "Resources verified successfully"

print_status "Worker cluster configured successfully"

# Step 2: Verify MultiKueue Service Account
echo -e "${BLUE}🔐 Step 2: Verifying MultiKueue service account...${NC}"

# Check if multikueue service account exists (should be created by manager script)
if kubectl get serviceaccount multikueue-sa -n kueue-system >/dev/null 2>&1; then
    print_status "MultiKueue service account exists on worker cluster"
else
    print_warning "MultiKueue service account not found. This should have been created by the manager configuration script."
    echo "If you encounter connection issues, ensure you ran './3-configure-manager-multikueue.sh' first."
fi

# Step 3: Verify Configuration
echo -e "${BLUE}✅ Step 3: Verifying worker cluster configuration...${NC}"

echo "Checking ClusterQueue status..."
run_cmd kubectl get clusterqueue worker-cluster-queue -n kueue-system -o yaml

echo "Checking LocalQueues status..."
run_cmd kubectl get localqueue -n multikueue-demo
run_cmd kubectl get localqueue -n default

echo "Checking ResourceFlavor status..."
run_cmd kubectl get resourceflavor -n kueue-system

print_status "Worker cluster MultiKueue configuration completed!"

echo ""
echo -e "${GREEN}🎉 Worker cluster MultiKueue configuration is ready!${NC}"
echo ""
echo "Worker cluster resources:"
echo "- ClusterQueue: worker-cluster-queue"
echo "- LocalQueue (multikueue-demo): manager-local-queue"
echo "- LocalQueue (default): default-local-queue"
echo ""
echo "Next steps:"
echo "1. Run './5-test-multikueue.sh' to test the complete MultiKueue setup"
echo ""
echo "To check worker cluster status:"
echo "- kubectl config use-context k3d-$WORKER_CLUSTER"
echo "- kubectl get clusterqueue,localqueue -A"
echo "- kubectl get pods -n kueue-system"
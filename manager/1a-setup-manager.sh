#!/bin/bash

# MultiKueue Manager Cluster Setup Script
# Sets up the manager Kubernetes cluster using Colima and kind
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
COLIMA_PROFILE="multikueue-manager"
MANAGER_CLUSTER="manager"
KUEUE_VERSION="v0.13.1"  # Latest as of August 2025

echo -e "${BLUE}🚀 Setting up MultiKueue Manager Cluster${NC}"
echo "========================================"

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

tools=("colima" "kubectl" "kind" "helm")
for tool in "${tools[@]}"; do
    if ! command -v "$tool" &> /dev/null; then
        echo "Installing $tool..."
        run_cmd brew install "$tool"
        print_status "$tool installed"
    else
        print_status "$tool already installed"
    fi
done

# Delete any existing manager Colima profile for a clean start
echo -e "${BLUE}🗑️  Deleting any existing manager Colima profile...${NC}"
run_cmd colima delete --profile $COLIMA_PROFILE --force 2>/dev/null || true
print_status "Existing manager Colima profile deleted"

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

# Create manager cluster (no custom network needed in separate VM setup)
echo -e "${BLUE}🏗️  Creating manager cluster: $MANAGER_CLUSTER${NC}"
run_cmd kind create cluster --config manager-config.yaml

print_status "Manager cluster '$MANAGER_CLUSTER' created"

# Verify cluster
echo -e "${BLUE}🔍 Verifying manager cluster context...${NC}"
run_cmd kubectl config use-context kind-$MANAGER_CLUSTER
run_cmd kubectl get nodes

# Install Kueue on manager cluster
echo -e "${BLUE}📦 Installing Kueue on manager cluster...${NC}"
run_cmd kubectl apply --server-side -f https://github.com/kubernetes-sigs/kueue/releases/download/$KUEUE_VERSION/manifests.yaml

print_status "Kueue installed on manager cluster"

# Wait for Kueue to be ready
echo -e "${BLUE}⏳ Waiting for Kueue components to be ready...${NC}"
echo "Waiting for Kueue components in manager cluster..."
run_cmd kubectl wait --for=condition=available --timeout=300s deployment/kueue-controller-manager -n kueue-system

print_status "Kueue components are ready on manager cluster"

echo ""
echo -e "${GREEN}🎉 Manager cluster setup completed successfully!${NC}"
echo ""
echo "Manager cluster information:"
echo "- Cluster name: kind-$MANAGER_CLUSTER"
echo "- Colima VM profile: $COLIMA_PROFILE"
echo "- API server: localhost:6443"
echo "- LoadBalancer ports: 80/443"
echo ""
echo "To check the cluster:"
echo "- kubectl config use-context kind-$MANAGER_CLUSTER"
echo "- kubectl get pods -n kueue-system"
echo ""
echo "Next steps:"
echo "- Copy your remote worker's remote-kubeconfig.yaml file to this directory."
echo "- Run 'export REMOTE_KUBECONFIG=remote-kubeconfig.yaml'"
echo "- Run ./1b-configure.manager.sh"

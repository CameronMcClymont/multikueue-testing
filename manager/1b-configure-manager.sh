#!/bin/bash

# MultiKueue Manager Configuration Script
# Configures MultiKueue resources on the manager cluster

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if REMOTE_KUBECONFIG env variable is set
if [ -z "${REMOTE_KUBECONFIG:-}" ]; then
    print_error "REMOTE_KUBECONFIG environment variable must be set"
    exit 1
fi

# Configuration
MANAGER_CLUSTER="manager"
# Use REMOTE_KUBECONFIG env variable as worker kubeconfig
WORKER_KUBECONFIG_FILE="$REMOTE_KUBECONFIG"
CURRENT_DIR=$(pwd)
TEMP_DIR="/tmp/multikueue-testing"

echo -e "${BLUE}⚙️  Configuring MultiKueue on Manager Cluster${NC}"
echo "============================================="

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

print_info() {
    echo -e "${CYAN}ℹ️  $1${NC}"
}

# Function to run commands with visible output
run_cmd() {
    echo -e "${YELLOW}$ $*${NC}"
    "$@"
}

# Function to clean up temporary files
cleanup_temp() {
    if [ -d "$TEMP_DIR" ]; then
        echo "Cleaning up temporary directory: $TEMP_DIR"
        rm -rf "$TEMP_DIR"
    fi
}

# Set up cleanup trap
trap cleanup_temp EXIT

# Create temporary directory
setup_temp_dir() {
    if [ -d "$TEMP_DIR" ]; then
        echo "Cleaning existing temporary directory: $TEMP_DIR"
        rm -rf "$TEMP_DIR"
    fi
    echo "Creating temporary directory: $TEMP_DIR"
    mkdir -p "$TEMP_DIR"
}

# Set up temporary directory
setup_temp_dir

# Check prerequisites
echo -e "${BLUE}📋 Checking prerequisites...${NC}"

# Check if manager cluster exists
if ! kubectl config get-contexts | grep -q "kind-$MANAGER_CLUSTER"; then
    print_error "Manager cluster 'kind-$MANAGER_CLUSTER' not found. Please run './1a-setup-manager.sh' first."
    exit 1
fi

print_status "Manager cluster is available"

# Check if worker kubeconfig exists from previous run
if [ -f "$WORKER_KUBECONFIG_FILE" ]; then
    print_warning "Worker kubeconfig '$WORKER_KUBECONFIG_FILE' exists."
else
    print_error "Worker kubeconfig '$WORKER_KUBECONFIG_FILE' not found. Please ensure you have copied over the kubeconfig file after running 'remote/configure-worker.sh' on your remote worker."
    exit 1
fi

# Step 1: Configure Manager Cluster
echo -e "${BLUE}🏗️  Step 1: Configuring manager cluster...${NC}"

# Switch to manager cluster context
echo "Switching to manager cluster context"
run_cmd kubectl config use-context kind-$MANAGER_CLUSTER

# Create secret with worker cluster kubeconfig
echo "Creating worker cluster secret in manager cluster..."
echo -e "${YELLOW}$ kubectl create secret generic worker-secret -n kueue-system --from-file=kubeconfig=\"$CURRENT_DIR/$WORKER_KUBECONFIG_FILE\" --dry-run=client -o yaml | kubectl apply -f -${NC}"
kubectl create secret generic worker-secret -n kueue-system \
    --from-file=kubeconfig="$CURRENT_DIR/$WORKER_KUBECONFIG_FILE" \
    --dry-run=client -o yaml | kubectl apply -f -

print_status "Worker cluster secret created in manager cluster"

# Apply manager cluster manifests
echo "Applying manager cluster manifests..."
run_cmd kubectl apply -f manager-manifests.yaml

# Verify manager cluster resources are created
echo "Verifying manager cluster resources..."
sleep 5

kubectl get clusterqueue/manager-cluster-queue -n kueue-system --no-headers >/dev/null
kubectl get localqueue/worker-queue -n multikueue-demo --no-headers >/dev/null
kubectl get localqueue/default-local-queue -n default --no-headers >/dev/null
kubectl get admissioncheck/multikueue-admission-check -n kueue-system --no-headers >/dev/null
kubectl get multikueueconfig/multikueue-config -n kueue-system --no-headers >/dev/null
kubectl get multikueuecluster/worker -n kueue-system --no-headers >/dev/null
echo "Resources verified successfully"

print_status "Manager cluster configured successfully"

# Step 2: Verify MultiKueue setup
echo -e "${BLUE}✅ Step 2: Verifying MultiKueue setup...${NC}"

echo "Checking AdmissionCheck status..."
run_cmd kubectl get admissioncheck multikueue-admission-check -n kueue-system -o yaml

echo "Checking MultiKueueConfig status..."
run_cmd kubectl get multikueueconfig multikueue-config -n kueue-system -o yaml

echo "Checking MultiKueueCluster status..."
run_cmd kubectl get multikueuecluster worker -n kueue-system -o yaml

echo "Checking ClusterQueue status..."
run_cmd kubectl get clusterqueue manager-cluster-queue -n kueue-system -o yaml

print_status "MultiKueue configuration on manager cluster completed!"

echo -e "${BLUE}🌐 Step 4: Remote cluster integration${NC}"
print_info "Remote cluster support is configured via './2c-configure-remote-multikueue.sh'"
if kubectl get secret remote-kubeconfig -n kueue-system > /dev/null 2>&1; then
    print_status "Remote cluster detected and configured"
else
    print_info "No remote cluster configured (optional)"
fi

echo ""
echo -e "${GREEN}🎉 Manager cluster MultiKueue configuration is ready!${NC}"
echo ""
echo "To check the status of MultiKueue components:"
echo "kubectl get multikueuecluster,multikueueconfig,admissioncheck -n kueue-system"

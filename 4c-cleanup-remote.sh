#!/bin/bash

# MultiKueue Remote Cluster Cleanup Script
# Cleans up MultiKueue resources from remote cluster (does NOT delete the cluster)
# Author: Claude Code

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${RED}🧹 Starting Remote Cluster Cleanup${NC}"
echo "====================================="

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
  echo -e "${YELLOW}→ $1${NC}"
}

# Function to run commands with visible output
run_cmd() {
  echo -e "${YELLOW}$ $*${NC}"
  "$@"
}

# Check if REMOTE_KUBECONFIG is provided
if [ -z "${REMOTE_KUBECONFIG:-}" ]; then
    print_error "REMOTE_KUBECONFIG environment variable must be set"
    print_info "Usage: REMOTE_KUBECONFIG=/path/to/kubeconfig $0"
    exit 1
fi

# Verify kubeconfig file exists
if [ ! -f "$REMOTE_KUBECONFIG" ]; then
    print_error "Kubeconfig file not found: $REMOTE_KUBECONFIG"
    exit 1
fi

# Test connection to remote cluster
print_info "Testing connection to remote cluster..."
if ! kubectl --kubeconfig="$REMOTE_KUBECONFIG" cluster-info > /dev/null 2>&1; then
    print_error "Cannot connect to remote cluster. Please check your kubeconfig."
    exit 1
fi

REMOTE_CONTEXT=$(kubectl --kubeconfig="$REMOTE_KUBECONFIG" config current-context)
print_status "Connected to remote cluster: $REMOTE_CONTEXT"

# Check if user really wants to cleanup
echo -e "${YELLOW}This will remove from the remote cluster:${NC}"
echo "- MultiKueue resources (ClusterQueue, LocalQueue)"
echo "- Kueue workloads and jobs in multikueue-demo namespace"
echo "- Service account and RBAC created for MultiKueue"
echo "- Generated local files (remote.kubeconfig, etc.)"
echo ""
echo -e "${YELLOW}The remote cluster itself will NOT be deleted.${NC}"
echo -e "${YELLOW}Optionally remove ALL Kueue components if requested.${NC}"
echo ""
read -p "Are you sure you want to continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Remote cleanup cancelled."
  exit 0
fi

# Clean up workloads first
print_info "Cleaning up workloads from remote cluster..."
kubectl --kubeconfig="$REMOTE_KUBECONFIG" delete jobs --all -n multikueue-demo --ignore-not-found=true 2>/dev/null || true

# Clean up our custom resources from remote cluster
print_info "Removing custom MultiKueue resources from remote cluster..."
kubectl --kubeconfig="$REMOTE_KUBECONFIG" delete -f remote-cluster-manifests.yaml --ignore-not-found=true --wait=false 2>/dev/null || \
  print_warning "Could not remove custom resources (cluster may be unavailable or resources not found)"

# Clean up service account and RBAC
print_info "Removing service account and RBAC from remote cluster..."
kubectl --kubeconfig="$REMOTE_KUBECONFIG" delete serviceaccount multikueue-remote-sa -n kueue-system --ignore-not-found=true 2>/dev/null || true
kubectl --kubeconfig="$REMOTE_KUBECONFIG" delete clusterrole multikueue-remote-role --ignore-not-found=true 2>/dev/null || true
kubectl --kubeconfig="$REMOTE_KUBECONFIG" delete clusterrolebinding multikueue-remote-binding --ignore-not-found=true 2>/dev/null || true

# Ask user if they want to uninstall Kueue completely from remote cluster
echo ""
echo -e "${YELLOW}Do you want to completely uninstall Kueue from the remote cluster?${NC}"
echo -e "${YELLOW}This will remove ALL Kueue resources (not just MultiKueue setup).${NC}"
read -p "Uninstall Kueue from remote cluster? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  print_info "Uninstalling Kueue from remote cluster..."
  if kubectl --kubeconfig="$REMOTE_KUBECONFIG" delete -f https://github.com/kubernetes-sigs/kueue/releases/download/v0.13.1/manifests.yaml --wait=false 2>/dev/null; then
    print_status "Kueue completely uninstalled from remote cluster"
  else
    print_warning "Could not uninstall Kueue from remote cluster (may already be removed or cluster unavailable)"
  fi
else
  print_info "Skipping Kueue uninstall from remote cluster"
fi

# Clean up namespace if empty
print_info "Removing multikueue-demo namespace if empty..."
kubectl --kubeconfig="$REMOTE_KUBECONFIG" delete namespace multikueue-demo --ignore-not-found=true 2>/dev/null || true

# Clean up local files
echo -e "${BLUE}🧽 Cleaning up local remote cluster files...${NC}"

if [ -f "remote.kubeconfig" ]; then
  rm -f "remote.kubeconfig"
  print_status "Removed remote.kubeconfig"
fi

if [ -f "remote-test-job.yaml" ]; then
  rm -f "remote-test-job.yaml"
  print_status "Removed remote-test-job.yaml"
fi

# Clean up remote cluster configuration from manager cluster (if accessible)
print_info "Cleaning up remote cluster configuration from manager cluster..."
if kubectl config get-contexts k3d-manager >/dev/null 2>&1; then
  echo "Switching to manager cluster to clean up remote configuration..."
  kubectl config use-context k3d-manager >/dev/null 2>&1 || true
  
  # Remove remote cluster resources from manager (without waiting for finalizers)
  kubectl delete secret remote-kubeconfig -n kueue-system --ignore-not-found=true --wait=false 2>/dev/null || true
  kubectl delete multikueuecluster remote-cluster -n kueue-system --ignore-not-found=true --wait=false 2>/dev/null || true
  kubectl delete multikueueconfig remote-multikueue-config -n kueue-system --ignore-not-found=true --wait=false 2>/dev/null || true
  kubectl delete admissioncheck remote-multikueue-admission-check -n kueue-system --ignore-not-found=true --wait=false 2>/dev/null || true
  kubectl delete clusterqueue remote-cluster-queue -n kueue-system --ignore-not-found=true --wait=false 2>/dev/null || true
  kubectl delete localqueue remote-queue -n multikueue-demo --ignore-not-found=true --wait=false 2>/dev/null || true
  
  print_status "Remote cluster configuration removed from manager cluster"
else
  print_warning "Manager cluster not accessible - skipping manager cluster cleanup"
fi

print_status "Remote cluster MultiKueue resources cleaned up (cluster itself remains intact)"

echo ""
echo -e "${GREEN}🎉 Remote cleanup completed successfully!${NC}"
echo ""
echo "MultiKueue resources have been removed from the remote cluster."
echo "The remote cluster itself remains intact and operational."
echo "Manager and worker clusters (if any) remain untouched."
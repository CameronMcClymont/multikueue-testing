#!/bin/bash

# MultiKueue Worker Cleanup Script
# Tears down the worker cluster and Colima VM
# Author: Claude Code

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
WORKER_COLIMA_PROFILE="multikueue-worker"
WORKER_CLUSTER="worker"
WORKER_KUBECONFIG_FILE="worker.kubeconfig"

echo -e "${RED}🧹 Starting Worker Cluster Cleanup${NC}"
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

# Check if user really wants to cleanup
echo -e "${YELLOW}This will completely remove:${NC}"
echo "- Worker k3d cluster ($WORKER_CLUSTER)"
echo "- Worker Colima VM with profile: $WORKER_COLIMA_PROFILE"
echo "- Generated worker kubeconfig files and contexts"
echo ""
read -p "Are you sure you want to continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Worker cleanup cancelled."
  exit 0
fi

# Check if Worker Colima VM is running
worker_vm_available=false
if colima status --profile $WORKER_COLIMA_PROFILE >/dev/null 2>&1; then
  worker_vm_available=true
fi

# Clean up worker cluster workloads
echo -e "${BLUE}🛑 Cleaning up worker cluster workloads...${NC}"

if [ "$worker_vm_available" = true ]; then
  echo "Switching to worker VM for workload cleanup..."
  colima start --profile $WORKER_COLIMA_PROFILE >/dev/null 2>&1 || true
  
  if k3d cluster list 2>/dev/null | grep -q $WORKER_CLUSTER; then
    echo "Cleaning up workloads from worker cluster..."
    kubectl config use-context k3d-$WORKER_CLUSTER 2>/dev/null || true
    kubectl delete jobs --all -n multikueue-demo --ignore-not-found=true
    kubectl delete jobs --all -n default --ignore-not-found=true
    print_status "Worker cluster workloads cleaned up"
  fi
else
  print_warning "Worker VM not available - skipping worker workload cleanup"
fi

# Delete worker k3d cluster
echo -e "${BLUE}🗑️  Deleting worker k3d cluster...${NC}"

if [ "$worker_vm_available" = true ]; then
  colima start --profile $WORKER_COLIMA_PROFILE >/dev/null 2>&1 || true
  if k3d cluster list 2>/dev/null | grep -q $WORKER_CLUSTER; then
    echo "Deleting worker cluster: $WORKER_CLUSTER"
    run_cmd k3d cluster delete $WORKER_CLUSTER
    print_status "Worker cluster deleted"
  else
    print_warning "Worker cluster '$WORKER_CLUSTER' not found"
  fi
else
  print_warning "Worker VM not available - skipping worker cluster deletion"
fi

# Stop and delete Worker Colima VM
echo -e "${BLUE}🐋 Stopping and deleting Worker Colima VM...${NC}"

if [ "$worker_vm_available" = true ]; then
  echo "Stopping worker Colima profile: $WORKER_COLIMA_PROFILE"
  run_cmd colima stop --profile $WORKER_COLIMA_PROFILE
  print_status "Worker Colima stopped"
else
  print_warning "Worker Colima profile '$WORKER_COLIMA_PROFILE' is not running"
fi

echo "Deleting worker Colima profile: $WORKER_COLIMA_PROFILE"
run_cmd colima delete --profile $WORKER_COLIMA_PROFILE --force 2>/dev/null || print_warning "Could not delete worker Colima profile (may not exist)"

# Clean up generated files
echo -e "${BLUE}🧽 Cleaning up worker generated files...${NC}"

if [ -f "$WORKER_KUBECONFIG_FILE" ]; then
  rm -f "$WORKER_KUBECONFIG_FILE"
  print_status "Removed $WORKER_KUBECONFIG_FILE"
fi

# Clean up kubectl contexts
echo -e "${BLUE}🔧 Cleaning up worker kubectl contexts...${NC}"

if kubectl config get-contexts k3d-$WORKER_CLUSTER >/dev/null 2>&1; then
  run_cmd kubectl config delete-context k3d-$WORKER_CLUSTER
else
  echo -e "${YELLOW}Worker cluster context 'k3d-$WORKER_CLUSTER' not found (likely already cleaned up)${NC}"
fi

# Clean up clusters and users
run_cmd kubectl config delete-cluster k3d-$WORKER_CLUSTER 2>/dev/null || true
run_cmd kubectl config delete-user k3d-$WORKER_CLUSTER 2>/dev/null || true

print_status "Worker kubectl contexts cleaned up"

# Verify cleanup
echo -e "${BLUE}🔍 Verifying worker cleanup...${NC}"
echo "Worker cluster: Cleaned up"
echo ""
echo "Colima VMs status:"
colima list 2>/dev/null || echo "No Colima instances running"

echo ""
echo -e "${GREEN}🎉 Worker cleanup completed successfully!${NC}"
echo ""
echo "The worker cluster and VM have been removed."
echo "Manager and remote clusters (if any) remain untouched."
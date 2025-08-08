#!/bin/bash

# MultiKueue Cleanup Script
# Tears down the entire MultiKueue setup including clusters and Colima
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
MANAGER_COLIMA_PROFILE="multikueue-manager"
WORKER_COLIMA_PROFILE="multikueue-worker"
MANAGER_CLUSTER="manager"
WORKER_CLUSTER="worker"
WORKER_KUBECONFIG_FILE="worker1.kubeconfig"

echo -e "${RED}🧹 Starting MultiKueue environment cleanup${NC}"
echo "=============================================="

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
echo "- Both k3d clusters ($MANAGER_CLUSTER and $WORKER_CLUSTER)"
echo "- Manager Colima VM with profile: $MANAGER_COLIMA_PROFILE"
echo "- Worker Colima VM with profile: $WORKER_COLIMA_PROFILE"
echo "- Generated kubeconfig files"
echo ""
read -p "Are you sure you want to continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Cleanup cancelled."
  exit 0
fi

# Check if Docker/Colima VMs are running before attempting k3d operations
manager_vm_available=false
worker_vm_available=false

if colima status --profile $MANAGER_COLIMA_PROFILE >/dev/null 2>&1; then
  manager_vm_available=true
fi

if colima status --profile $WORKER_COLIMA_PROFILE >/dev/null 2>&1; then
  worker_vm_available=true
fi

# Stop and clean up sample workloads first
echo -e "${BLUE}🛑 Cleaning up sample workloads...${NC}"

# Clean up manager cluster workloads
if [ "$manager_vm_available" = true ]; then
  echo "Switching to manager VM for workload cleanup..."
  colima start --profile $MANAGER_COLIMA_PROFILE >/dev/null 2>&1 || true
  
  if k3d cluster list 2>/dev/null | grep -q $MANAGER_CLUSTER; then
    echo "Cleaning up workloads from manager cluster..."
    kubectl config use-context k3d-$MANAGER_CLUSTER 2>/dev/null || true
    kubectl delete job multikueue-test-job -n multikueue-demo --ignore-not-found=true
    kubectl delete job multikueue-simple-test -n multikueue-demo --ignore-not-found=true
    print_status "Manager cluster workloads cleaned up"
  fi
else
  print_warning "Manager VM not available - skipping manager workload cleanup"
fi

# Clean up worker cluster workloads
if [ "$worker_vm_available" = true ]; then
  echo "Switching to worker VM for workload cleanup..."
  colima start --profile $WORKER_COLIMA_PROFILE >/dev/null 2>&1 || true
  
  if k3d cluster list 2>/dev/null | grep -q $WORKER_CLUSTER; then
    echo "Cleaning up workloads from worker cluster..."
    kubectl config use-context k3d-$WORKER_CLUSTER 2>/dev/null || true
    kubectl delete pod worker-test-pod -n multikueue-demo --ignore-not-found=true
    print_status "Worker cluster workloads cleaned up"
  fi
else
  print_warning "Worker VM not available - skipping worker workload cleanup"
fi

# Delete k3d clusters
echo -e "${BLUE}🗑️  Deleting k3d clusters...${NC}"

# Delete manager cluster
if [ "$manager_vm_available" = true ]; then
  colima start --profile $MANAGER_COLIMA_PROFILE >/dev/null 2>&1 || true
  if k3d cluster list 2>/dev/null | grep -q $MANAGER_CLUSTER; then
    echo "Deleting manager cluster: $MANAGER_CLUSTER"
    run_cmd k3d cluster delete $MANAGER_CLUSTER
    print_status "Manager cluster deleted"
  else
    print_warning "Manager cluster '$MANAGER_CLUSTER' not found"
  fi
else
  print_warning "Manager VM not available - skipping manager cluster deletion"
fi

# Delete worker cluster  
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

# Stop and delete Colima VMs
echo -e "${BLUE}🐋 Stopping and deleting Colima VMs...${NC}"

# Stop and delete manager VM
if [ "$manager_vm_available" = true ]; then
  echo "Stopping manager Colima profile: $MANAGER_COLIMA_PROFILE"
  run_cmd colima stop --profile $MANAGER_COLIMA_PROFILE
  print_status "Manager Colima stopped"
else
  print_warning "Manager Colima profile '$MANAGER_COLIMA_PROFILE' is not running"
fi

echo "Deleting manager Colima profile: $MANAGER_COLIMA_PROFILE"
run_cmd colima delete --profile $MANAGER_COLIMA_PROFILE --force 2>/dev/null || print_warning "Could not delete manager Colima profile (may not exist)"

# Stop and delete worker VM
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
echo -e "${BLUE}🧽 Cleaning up generated files...${NC}"

if [ -f "$WORKER_KUBECONFIG_FILE" ]; then
  rm -f "$WORKER_KUBECONFIG_FILE"
  print_status "Removed $WORKER_KUBECONFIG_FILE"
fi

# Clean up kubectl contexts (optional)
echo -e "${BLUE}🔧 Cleaning up kubectl contexts...${NC}"

# Check if contexts exist before trying to delete them
if kubectl config get-contexts k3d-$MANAGER_CLUSTER >/dev/null 2>&1; then
  run_cmd kubectl config delete-context k3d-$MANAGER_CLUSTER
else
  echo -e "${YELLOW}Manager cluster context 'k3d-$MANAGER_CLUSTER' not found (likely already cleaned up)${NC}"
fi

if kubectl config get-contexts k3d-$WORKER_CLUSTER >/dev/null 2>&1; then
  run_cmd kubectl config delete-context k3d-$WORKER_CLUSTER
else
  echo -e "${YELLOW}Worker cluster context 'k3d-$WORKER_CLUSTER' not found (likely already cleaned up)${NC}"
fi

# Clean up clusters and users (these may have been auto-cleaned by k3d)
run_cmd kubectl config delete-cluster k3d-$MANAGER_CLUSTER 2>/dev/null || true
run_cmd kubectl config delete-cluster k3d-$WORKER_CLUSTER 2>/dev/null || true

run_cmd kubectl config delete-user k3d-$MANAGER_CLUSTER 2>/dev/null || true
run_cmd kubectl config delete-user k3d-$WORKER_CLUSTER 2>/dev/null || true

print_status "kubectl contexts cleaned up"

# Verify cleanup
echo -e "${BLUE}🔍 Verifying cleanup...${NC}"

echo "k3d clusters: Cleaned up (all Colima VMs stopped)"

echo ""
echo "Colima VMs status:"
colima list 2>/dev/null || echo "No Colima instances running"

echo ""
echo -e "${GREEN}🎉 Cleanup completed successfully!${NC}"
echo ""
echo "All MultiKueue resources have been removed from your system."
echo ""
echo "To start fresh, run the setup scripts in order:"
echo "1. ./1-setup-manager-cluster.sh    (creates manager VM)"
echo "2. ./2-setup-worker-cluster.sh     (creates worker VM)"
echo "3. ./3-configure-manager-multikueue.sh"
echo "4. ./4-configure-worker-multikueue.sh"
echo "5. ./5-test-multikueue.sh"
echo ""
echo "The new architecture uses separate VMs:"
echo "- Manager VM: multikueue-manager (localhost:6443)"
echo "- Worker VM: multikueue-worker (localhost:6444)"


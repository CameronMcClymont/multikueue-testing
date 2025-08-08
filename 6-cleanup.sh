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
COLIMA_PROFILE="multikueue"
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
echo "- Colima instance with profile: $COLIMA_PROFILE"
echo "- Generated kubeconfig files"
echo ""
read -p "Are you sure you want to continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Cleanup cancelled."
  exit 0
fi

# Check if Docker/Colima is running before attempting k3d operations
docker_available=false
if colima status --profile $COLIMA_PROFILE >/dev/null 2>&1; then
  docker_available=true
fi

# Stop and clean up sample workloads first
echo -e "${BLUE}🛑 Cleaning up sample workloads...${NC}"

if [ "$docker_available" = true ]; then
  # Check if clusters exist and clean up workloads
  if k3d cluster list 2>/dev/null | grep -q $MANAGER_CLUSTER; then
    echo "Cleaning up workloads from manager cluster..."
    kubectl config use-context k3d-$MANAGER_CLUSTER 2>/dev/null || true
    kubectl delete job multikueue-test-job -n multikueue-demo --ignore-not-found=true
    kubectl delete job multikueue-simple-test -n multikueue-demo --ignore-not-found=true
    print_status "Manager cluster workloads cleaned up"
  fi

  if k3d cluster list 2>/dev/null | grep -q $WORKER_CLUSTER; then
    echo "Cleaning up workloads from worker cluster..."
    kubectl config use-context k3d-$WORKER_CLUSTER 2>/dev/null || true
    kubectl delete pod worker-test-pod -n multikueue-demo --ignore-not-found=true
    print_status "Worker cluster workloads cleaned up"
  fi
else
  print_warning "Docker not available - skipping workload cleanup (clusters likely already removed)"
fi

# Delete k3d clusters
echo -e "${BLUE}🗑️  Deleting k3d clusters...${NC}"

if [ "$docker_available" = true ]; then
  # Delete manager cluster
  if k3d cluster list 2>/dev/null | grep -q $MANAGER_CLUSTER; then
    echo "Deleting manager cluster: $MANAGER_CLUSTER"
    run_cmd k3d cluster delete $MANAGER_CLUSTER
    print_status "Manager cluster deleted"
  else
    print_warning "Manager cluster '$MANAGER_CLUSTER' not found"
  fi

  # Delete worker cluster
  if k3d cluster list 2>/dev/null | grep -q $WORKER_CLUSTER; then
    echo "Deleting worker cluster: $WORKER_CLUSTER"
    run_cmd k3d cluster delete $WORKER_CLUSTER
    print_status "Worker cluster deleted"
  else
    print_warning "Worker cluster '$WORKER_CLUSTER' not found"
  fi
else
  print_warning "Docker not available - skipping k3d cluster deletion (likely already cleaned up)"
fi

# Clean up Docker network before stopping Colima
if [ "$docker_available" = true ]; then
  echo "Cleaning up Docker network..."
  docker network rm multikueue-network 2>/dev/null || print_warning "Could not remove Docker network (may not exist)"
else
  print_warning "Docker not available - skipping Docker network cleanup"
fi

# Stop Colima
echo -e "${BLUE}🐋 Stopping Colima...${NC}"
if colima status --profile $COLIMA_PROFILE >/dev/null 2>&1; then
  echo "Stopping Colima profile: $COLIMA_PROFILE"
  colima stop --profile $COLIMA_PROFILE
  print_status "Colima stopped"
else
  print_warning "Colima profile '$COLIMA_PROFILE' is not running"
fi

# Delete Colima profile
echo "Deleting Colima profile: $COLIMA_PROFILE"
run_cmd colima delete --profile $COLIMA_PROFILE --force 2>/dev/null || print_warning "Could not delete Colima profile (may not exist)"

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

# Only check k3d if Colima is still running (has Docker access)
if colima status --profile $COLIMA_PROFILE >/dev/null 2>&1; then
  echo "Remaining k3d clusters:"
  k3d cluster list 2>/dev/null || echo "No k3d clusters found"
else
  echo "k3d clusters: Cleaned up (Colima stopped)"
fi

echo ""
echo "Colima status:"
colima list 2>/dev/null || echo "No Colima instances running"

echo ""
echo -e "${GREEN}🎉 Cleanup completed successfully!${NC}"
echo ""
echo "All MultiKueue resources have been removed from your system."
echo ""
echo "To start fresh, run the setup scripts in order:"
echo "1. ./1-setup-manager-cluster.sh"
echo "2. ./2-setup-worker-cluster.sh"
echo "3. ./3-configure-manager-multikueue.sh"
echo "4. ./4-configure-worker-multikueue.sh"
echo "5. ./5-test-multikueue.sh"


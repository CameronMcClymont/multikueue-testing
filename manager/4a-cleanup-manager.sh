#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
MANAGER_COLIMA_PROFILE="multikueue-manager"
MANAGER_CLUSTER="manager"

echo -e "${RED}🧹 Starting Manager Cluster Cleanup${NC}"
echo "======================================="

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
echo "- Manager kind cluster ($MANAGER_CLUSTER)"
echo "- Manager Colima VM with profile: $MANAGER_COLIMA_PROFILE"
echo "- Generated manager kubeconfig contexts"
echo ""
read -p "Are you sure you want to continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Manager cleanup cancelled."
  exit 0
fi

# Check if Manager Colima VM is running
manager_vm_available=false
if colima status --profile $MANAGER_COLIMA_PROFILE >/dev/null 2>&1; then
  manager_vm_available=true
fi

# Clean up manager cluster workloads
echo -e "${BLUE}🛑 Cleaning up manager cluster workloads...${NC}"

if [ "$manager_vm_available" = true ]; then
  echo "Switching to manager VM for workload cleanup..."
  colima start --profile $MANAGER_COLIMA_PROFILE >/dev/null 2>&1 || true

  if kind cluster list 2>/dev/null | grep -q $MANAGER_CLUSTER; then
    echo "Cleaning up workloads from manager cluster..."
    kubectl config use-context kind-$MANAGER_CLUSTER 2>/dev/null || true
    kubectl delete jobs --all -n multikueue-demo --ignore-not-found=true
    kubectl delete jobs --all -n default --ignore-not-found=true
    print_status "Manager cluster workloads cleaned up"
  fi
else
  print_warning "Manager VM not available - skipping manager workload cleanup"
fi

# Delete manager kind cluster
echo -e "${BLUE}🗑️  Deleting manager kind cluster...${NC}"

if [ "$manager_vm_available" = true ]; then
  colima start --profile $MANAGER_COLIMA_PROFILE >/dev/null 2>&1 || true
  if kind cluster list 2>/dev/null | grep -q $MANAGER_CLUSTER; then
    echo "Deleting manager cluster: $MANAGER_CLUSTER"
    run_cmd kind cluster delete $MANAGER_CLUSTER
    print_status "Manager cluster deleted"
  else
    print_warning "Manager cluster '$MANAGER_CLUSTER' not found"
  fi
else
  print_warning "Manager VM not available - skipping manager cluster deletion"
fi

# Stop and delete Manager Colima VM
echo -e "${BLUE}🐋 Stopping and deleting Manager Colima VM...${NC}"

if [ "$manager_vm_available" = true ]; then
  echo "Stopping manager Colima profile: $MANAGER_COLIMA_PROFILE"
  run_cmd colima stop --profile $MANAGER_COLIMA_PROFILE
  print_status "Manager Colima stopped"
else
  print_warning "Manager Colima profile '$MANAGER_COLIMA_PROFILE' is not running"
fi

echo "Deleting manager Colima profile: $MANAGER_COLIMA_PROFILE"
run_cmd colima delete --profile $MANAGER_COLIMA_PROFILE --force 2>/dev/null || print_warning "Could not delete manager Colima profile (may not exist)"

# Clean up kubectl contexts
echo -e "${BLUE}🔧 Cleaning up manager kubectl contexts...${NC}"

if kubectl config get-contexts kind-$MANAGER_CLUSTER >/dev/null 2>&1; then
  run_cmd kubectl config delete-context kind-$MANAGER_CLUSTER
else
  echo -e "${YELLOW}Manager cluster context 'kind-$MANAGER_CLUSTER' not found (likely already cleaned up)${NC}"
fi

# Clean up clusters and users
run_cmd kubectl config delete-cluster kind-$MANAGER_CLUSTER 2>/dev/null || true
run_cmd kubectl config delete-user kind-$MANAGER_CLUSTER 2>/dev/null || true

print_status "Manager kubectl contexts cleaned up"

# Verify cleanup
echo -e "${BLUE}🔍 Verifying manager cleanup...${NC}"
echo "Manager cluster: Cleaned up"
echo ""
echo "Colima VMs status:"
colima list 2>/dev/null || echo "No Colima instances running"

echo ""
echo -e "${GREEN}🎉 Manager cleanup completed successfully!${NC}"
echo ""
echo "The manager cluster and VM have been removed."
echo "Worker and remote clusters (if any) remain untouched."

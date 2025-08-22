#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
MANAGER_CLUSTER="manager"

echo -e "${BLUE}🧪 Testing MultiKueue Manager Cluster${NC}"
echo "===================================="

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

# Check prerequisites
echo -e "${BLUE}📋 Checking prerequisites...${NC}"

# Check if manager cluster exists and is accessible
if ! kubectl config get-contexts | grep -q "kind-$MANAGER_CLUSTER"; then
    print_error "Manager cluster 'kind-$MANAGER_CLUSTER' not found. Please run './1a-setup-manager-cluster.sh' first."
    exit 1
fi

# Switch to manager cluster context
echo "Switching to manager cluster context..."
run_cmd kubectl config use-context kind-$MANAGER_CLUSTER

print_status "Manager cluster is accessible"

# Step 1: Verify MultiKueue Installation
echo -e "${BLUE}🔍 Step 1: Verifying MultiKueue installation...${NC}"

if kubectl get deployment kueue-controller-manager -n kueue-system >/dev/null 2>&1; then
    print_status "Kueue controller manager is installed"

    # Check if it's running
    if kubectl get pods -n kueue-system -l control-plane=controller-manager --field-selector=status.phase=Running >/dev/null 2>&1; then
        print_status "Kueue controller manager is running"
    else
        print_warning "Kueue controller manager may not be running properly"
    fi
else
    print_error "Kueue controller manager not found. Please run './2a-configure-manager-multikueue.sh' first."
    exit 1
fi

# Step 2: Inspect MultiKueue Configuration
echo -e "${BLUE}⚙️  Step 2: Inspecting MultiKueue configuration...${NC}"

echo "Checking MultiKueueConfigs..."
if kubectl get multikueueconfigs -n kueue-system >/dev/null 2>&1; then
    run_cmd kubectl get multikueueconfigs -n kueue-system -o wide
    echo ""

    # Show detailed config for each
    for config in $(kubectl get multikueueconfigs -n kueue-system -o name 2>/dev/null || echo ""); do
        if [ -n "$config" ]; then
            echo "Details for $config:"
            run_cmd kubectl get "$config" -n kueue-system -o yaml
            echo ""
        fi
    done
else
    print_info "No MultiKueueConfigs found (this is normal if only using local worker cluster)"
fi

echo "Checking MultiKueueClusters..."
if kubectl get multikueueclusters -n kueue-system >/dev/null 2>&1; then
    run_cmd kubectl get multikueueclusters -n kueue-system -o wide
    echo ""

    # Show status for each remote cluster
    for cluster in $(kubectl get multikueueclusters -n kueue-system -o name 2>/dev/null || echo ""); do
        if [ -n "$cluster" ]; then
            echo "Details for $cluster:"
            run_cmd kubectl get "$cluster" -n kueue-system -o yaml
            echo ""
        fi
    done
else
    print_info "No MultiKueueClusters found (this is normal if only using local worker cluster)"
fi

# Step 3: Check ClusterQueues and AdmissionChecks
echo -e "${BLUE}🎯 Step 3: Checking ClusterQueues and AdmissionChecks...${NC}"

echo "ClusterQueues on manager cluster:"
run_cmd kubectl get clusterqueues -n kueue-system -o wide

echo ""
echo "AdmissionChecks on manager cluster:"
run_cmd kubectl get admissionchecks -n kueue-system -o wide

echo ""
echo "LocalQueues in all namespaces:"
run_cmd kubectl get localqueues -A -o wide

# Step 4: Manager Cluster Payload Policy
echo -e "${BLUE}📝 Step 4: Manager cluster payload policy...${NC}"

print_info "IMPORTANT: The manager cluster is designed for orchestration only."
print_info "Jobs submitted to manager cluster queues are dispatched to worker/remote clusters."
print_info "The manager cluster typically does not run workloads directly."

echo ""
echo -e "${CYAN}Available queues on manager cluster:${NC}"

# List available LocalQueues that users can submit to
if kubectl get localqueues -A >/dev/null 2>&1; then
    kubectl get localqueues -A --no-headers | while read -r namespace name rest; do
        echo "  • $namespace/$name"

        # Get the target ClusterQueue
        target_cq=$(kubectl get localqueue "$name" -n "$namespace" -o jsonpath='{.spec.clusterQueue}' 2>/dev/null || echo "unknown")

        # Check if it has admission checks (indicates MultiKueue dispatch)
        if kubectl get clusterqueue "$target_cq" -n kueue-system -o jsonpath='{.spec.admissionChecks}' 2>/dev/null | grep -q "multikueue"; then
            echo "    → Dispatches to remote cluster via MultiKueue"
        else
            echo "    → Runs locally on manager cluster"
        fi
    done
else
    print_info "No LocalQueues configured"
fi

# Step 5: Connection Test to Remote Clusters
echo -e "${BLUE}🌐 Step 5: Testing connections to remote clusters...${NC}"

if kubectl get multikueueclusters -n kueue-system >/dev/null 2>&1; then
    echo "Testing connectivity to configured remote clusters..."

    for cluster in $(kubectl get multikueueclusters -n kueue-system -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo ""); do
        echo ""
        echo "Testing connection to cluster: $cluster"

        # Check the cluster status in MultiKueueCluster resource
        status=$(kubectl get multikueuecluster "$cluster" -n kueue-system -o jsonpath='{.status.conditions[?(@.type=="Active")].status}' 2>/dev/null || echo "Unknown")

        if [ "$status" = "True" ]; then
            print_status "Cluster $cluster is active and reachable"
        elif [ "$status" = "False" ]; then
            print_warning "Cluster $cluster is not active - check connection"
        else
            print_info "Cluster $cluster status: $status"
        fi
    done
else
    print_info "No remote clusters configured - manager will dispatch to local worker cluster only"
fi

echo ""
echo -e "${GREEN}🎉 Manager cluster MultiKueue testing completed!${NC}"
echo ""

echo -e "${CYAN}📋 Summary:${NC}"
echo "• Manager cluster is running and configured for MultiKueue orchestration"
echo "• Jobs submitted to manager queues will be dispatched to worker/remote clusters"
echo "• Manager cluster serves as the central control plane for multi-cluster job scheduling"

echo ""
echo -e "${CYAN}To monitor MultiKueue activity:${NC}"
echo "• Check controller logs: kubectl logs -n kueue-system deployment/kueue-controller-manager -f"
echo "• Watch workloads: kubectl get workloads -A --watch"
echo "• Monitor job flow: kubectl get jobs -A --watch"

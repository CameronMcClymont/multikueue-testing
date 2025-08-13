#!/bin/bash

# MultiKueue Manager Configuration Script
# Configures MultiKueue resources on the manager cluster
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
MANAGER_CLUSTER="manager"
WORKER_CLUSTER="worker"
WORKER_KUBECONFIG_FILE="worker1.kubeconfig"
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
if ! kubectl config get-contexts | grep -q "k3d-$MANAGER_CLUSTER"; then
    print_error "Manager cluster 'k3d-$MANAGER_CLUSTER' not found. Please run './1-setup-manager-cluster.sh' first."
    exit 1
fi

# Check if worker cluster exists
if ! kubectl config get-contexts | grep -q "k3d-$WORKER_CLUSTER"; then
    print_error "Worker cluster 'k3d-$WORKER_CLUSTER' not found. Please run './2-setup-worker-cluster.sh' first."
    exit 1
fi

print_status "Both clusters are available"

# Check if worker kubeconfig already exists from previous run
if [ -f "$WORKER_KUBECONFIG_FILE" ]; then
    print_warning "Worker kubeconfig '$WORKER_KUBECONFIG_FILE' already exists. Using existing file."
    use_existing_kubeconfig=true
else
    use_existing_kubeconfig=false
fi

# Step 1: Generate worker cluster kubeconfig if needed
if [ "$use_existing_kubeconfig" = false ]; then
    echo -e "${BLUE}🔑 Step 1: Creating MultiKueue service account for worker cluster...${NC}"
    
    # Switch to worker cluster context (should already be available from previous setup)
    echo "Switching to worker cluster context to create service account"
    run_cmd kubectl config use-context k3d-$WORKER_CLUSTER
    
    # Create service account and RBAC
    echo -e "${YELLOW}$ kubectl apply -f - <<EOF${NC}"
    cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: multikueue-sa
  namespace: kueue-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: multikueue-role
rules:
- apiGroups: [""]
  resources: ["namespaces"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["kueue.x-k8s.io"]
  resources: ["workloads", "localqueues", "clusterqueues", "resourceflavors"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["batch"]
  resources: ["jobs"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: multikueue-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: multikueue-sa
  namespace: kueue-system
EOF
    
    # Verify service account was created
    kubectl get serviceaccount/multikueue-sa -n kueue-system --no-headers >/dev/null
    
    # Get the service account token
    echo "Creating service account token..."
    echo -e "${YELLOW}$ kubectl apply -f - <<EOF${NC}"
    kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: multikueue-sa-token
  namespace: kueue-system
  annotations:
    kubernetes.io/service-account.name: multikueue-sa
type: kubernetes.io/service-account-token
EOF
    
    # Wait for token to be created
    sleep 5
    
    # Generate kubeconfig for worker cluster
    echo "Generating kubeconfig for worker cluster..."
    
    # For separate VM setup, detect the host machine's IP that's accessible from manager VM
    echo "Detecting host IP for cross-VM communication..."
    
    # Try multiple methods to detect the correct IP address
    HOST_IP=""
    
    # Method 1: Check Colima network gateway from manager VM
    if command -v colima >/dev/null 2>&1; then
        echo "Attempting to detect Colima network gateway..."
        # Use temp file to capture gateway detection
        GATEWAY_FILE="$TEMP_DIR/colima_gateway.txt"
        if colima ssh -p multikueue-manager -- ip route 2>/dev/null | grep '^default' | awk '{print $3}' | head -1 > "$GATEWAY_FILE" 2>/dev/null; then
            HOST_IP=$(cat "$GATEWAY_FILE" 2>/dev/null || echo "")
            if [ -n "$HOST_IP" ] && [ "$HOST_IP" != "127.0.0.1" ]; then
                echo "Found Colima network gateway: $HOST_IP"
            else
                HOST_IP=""
            fi
        fi
    fi
    
    # Method 2: Try common Docker/VM network gateways
    if [ -z "$HOST_IP" ]; then
        echo "Trying common container network gateways..."
        for candidate_ip in "host.docker.internal" "192.168.65.1" "192.168.106.1" "172.17.0.1"; do
            if curl -k --connect-timeout 2 "https://$candidate_ip:6444/api" >/dev/null 2>&1; then
                HOST_IP="$candidate_ip"
                echo "Found working host IP: $HOST_IP"
                break
            fi
        done
    fi
    
    # Method 3: Fallback to detecting host's external IP
    if [ -z "$HOST_IP" ]; then
        echo "Detecting host machine's external IP..."
        # Try to get the host's IP on the shared network
        HOST_IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "")
        if [ -z "$HOST_IP" ]; then
            HOST_IP=$(ipconfig getifaddr en0 2>/dev/null || echo "")
        fi
        if [ -n "$HOST_IP" ]; then
            echo "Using host external IP: $HOST_IP"
        fi
    fi
    
    # Final fallback
    if [ -z "$HOST_IP" ]; then
        print_warning "Could not auto-detect host IP. Using localhost as fallback."
        print_warning "If connection fails, you may need to manually determine the correct IP."
        HOST_IP="127.0.0.1"
    fi
    
    CLUSTER_SERVER="https://$HOST_IP:6444"
    echo "Using worker cluster endpoint: $CLUSTER_SERVER"
    
    # Get service account token
    echo "Extracting service account token..."
    TOKEN_FILE="$TEMP_DIR/sa_token.txt"
    if kubectl get secret multikueue-sa-token -n kueue-system -o jsonpath='{.data.token}' | base64 -d > "$TOKEN_FILE" 2>/dev/null; then
        SA_TOKEN=$(cat "$TOKEN_FILE")
        echo "Service account token extracted successfully"
    else
        print_error "Failed to extract service account token"
        exit 1
    fi
    
    # Create kubeconfig file
    # Note: Using insecure-skip-tls-verify because the certificate is not valid for the IP address
    cat > $WORKER_KUBECONFIG_FILE <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    insecure-skip-tls-verify: true
    server: $CLUSTER_SERVER
  name: worker-cluster
contexts:
- context:
    cluster: worker-cluster
    user: multikueue-sa
  name: worker-cluster
current-context: worker-cluster
users:
- name: multikueue-sa
  user:
    token: $SA_TOKEN
EOF
    
    print_status "Worker cluster kubeconfig created: $WORKER_KUBECONFIG_FILE"
else
    print_status "Using existing worker kubeconfig: $WORKER_KUBECONFIG_FILE"
fi

# Step 2: Configure Manager Cluster
echo -e "${BLUE}🏗️  Step 2: Configuring manager cluster...${NC}"

# Switch to manager cluster context
echo "Switching to manager cluster context"
run_cmd kubectl config use-context k3d-$MANAGER_CLUSTER

# Create secret with worker cluster kubeconfig
echo "Creating worker cluster secret in manager cluster..."
echo -e "${YELLOW}$ kubectl create secret generic worker1-secret -n kueue-system --from-file=kubeconfig=\"$CURRENT_DIR/$WORKER_KUBECONFIG_FILE\" --dry-run=client -o yaml | kubectl apply -f -${NC}"
kubectl create secret generic worker1-secret -n kueue-system \
    --from-file=kubeconfig="$CURRENT_DIR/$WORKER_KUBECONFIG_FILE" \
    --dry-run=client -o yaml | kubectl apply -f -

print_status "Worker cluster secret created in manager cluster"

# Apply manager cluster manifests
echo "Applying manager cluster manifests..."
run_cmd kubectl apply -f manager-cluster-manifests.yaml

# Verify manager cluster resources are created
echo "Verifying manager cluster resources..."
sleep 5

kubectl get clusterqueue/manager-cluster-queue -n kueue-system --no-headers >/dev/null
kubectl get localqueue/manager-local-queue -n multikueue-demo --no-headers >/dev/null  
kubectl get localqueue/default-local-queue -n default --no-headers >/dev/null
kubectl get admissioncheck/multikueue-admission-check -n kueue-system --no-headers >/dev/null
kubectl get multikueueconfig/multikueue-config -n kueue-system --no-headers >/dev/null
kubectl get multikueuecluster/worker1 -n kueue-system --no-headers >/dev/null
echo "Resources verified successfully"

print_status "Manager cluster configured successfully"

# Step 3: Verify MultiKueue setup
echo -e "${BLUE}✅ Step 3: Verifying MultiKueue setup...${NC}"

echo "Checking AdmissionCheck status..."
run_cmd kubectl get admissioncheck multikueue-admission-check -n kueue-system -o yaml

echo "Checking MultiKueueConfig status..."
run_cmd kubectl get multikueueconfig multikueue-config -n kueue-system -o yaml

echo "Checking MultiKueueCluster status..."
run_cmd kubectl get multikueuecluster worker1 -n kueue-system -o yaml

echo "Checking ClusterQueue status..."
run_cmd kubectl get clusterqueue manager-cluster-queue -n kueue-system -o yaml

print_status "MultiKueue configuration on manager cluster completed!"

echo ""
echo -e "${GREEN}🎉 Manager cluster MultiKueue configuration is ready!${NC}"
echo ""
echo "Next steps:"
echo "1. Run './4-configure-worker-multikueue.sh' to configure worker cluster"
echo "2. Run './5-test-multikueue.sh' to test the complete setup"
echo ""
echo "To check the status of MultiKueue components:"
echo "kubectl get multikueuecluster,multikueueconfig,admissioncheck -n kueue-system"
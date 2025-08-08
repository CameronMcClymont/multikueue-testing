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
    
    # Switch to worker cluster
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
  name: multikueue-role
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
    
    # Get cluster info
    CLUSTER_NAME=$(kubectl config current-context)
    CLUSTER_CA=$(kubectl config view --raw -o jsonpath='{.clusters[?(@.name=="'"$CLUSTER_NAME"'")].cluster.certificate-authority-data}')
    
    # Use internal k3d network address instead of localhost
    CLUSTER_SERVER="https://k3d-${WORKER_CLUSTER}-server-0:6443"
    
    # Get service account token
    SA_TOKEN=$(kubectl get secret multikueue-sa-token -n kueue-system -o jsonpath='{.data.token}' | base64 -d)
    
    # Create kubeconfig file
    cat > $WORKER_KUBECONFIG_FILE <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: $CLUSTER_CA
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
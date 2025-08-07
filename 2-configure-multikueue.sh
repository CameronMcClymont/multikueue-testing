#!/bin/bash

# MultiKueue Configuration Script
# Configures MultiKueue on both manager and worker clusters
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

echo -e "${BLUE}⚙️  Configuring MultiKueue environment${NC}"
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

# Function to wait for resource to be ready
wait_for_resource() {
    local resource_type=$1
    local resource_name=$2
    local namespace=${3:-"kueue-system"}
    
    echo "Waiting for $resource_type/$resource_name to be ready in namespace $namespace..."
    kubectl wait --for=condition=ready --timeout=300s "$resource_type/$resource_name" -n "$namespace" 2>/dev/null || true
}

# Step 1: Configure Worker Cluster
echo -e "${BLUE}🔧 Step 1: Configuring worker cluster...${NC}"
run_cmd kubectl config use-context k3d-$WORKER_CLUSTER

# Apply worker cluster manifests
echo "Applying worker cluster manifests..."
run_cmd kubectl apply -f worker-cluster-manifests.yaml

# Verify worker cluster resources are created
echo "Verifying worker cluster resources..."
kubectl get clusterqueue/worker-cluster-queue -n kueue-system --no-headers >/dev/null
kubectl get localqueue/manager-local-queue -n multikueue-demo --no-headers >/dev/null
kubectl get localqueue/default-local-queue -n default --no-headers >/dev/null
echo "Resources verified successfully"

print_status "Worker cluster configured successfully"

# Step 2: Create MultiKueue service account and kubeconfig for worker cluster
echo -e "${BLUE}🔑 Step 2: Creating MultiKueue service account for worker cluster...${NC}"

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
# Only basic permissions needed for Jobs and core Kubernetes resources
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
# The worker cluster is accessible from manager cluster via the k3d internal network
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

# Step 3: Configure Manager Cluster
echo -e "${BLUE}🏗️  Step 3: Configuring manager cluster...${NC}"
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

# Step 4: Verify MultiKueue setup
echo -e "${BLUE}✅ Step 4: Verifying MultiKueue setup...${NC}"

echo "Checking AdmissionCheck status..."
run_cmd kubectl get admissioncheck multikueue-admission-check -n kueue-system -o yaml

echo "Checking MultiKueueConfig status..."
run_cmd kubectl get multikueueconfig multikueue-config -n kueue-system -o yaml

echo "Checking MultiKueueCluster status..."
run_cmd kubectl get multikueuecluster worker1 -n kueue-system -o yaml

echo "Checking ClusterQueue status..."
run_cmd kubectl get clusterqueue manager-cluster-queue -n kueue-system -o yaml

print_status "MultiKueue configuration completed!"

echo ""
echo -e "${GREEN}🎉 MultiKueue is now ready for use!${NC}"
echo ""
echo "To test the setup:"
echo -e "${BLUE}Recommended: Use the automated test helper${NC}"
echo "  ./3-test-multikueue.sh"
echo ""
echo "Or test manually:"
echo "1. Switch to manager cluster: kubectl config use-context k3d-$MANAGER_CLUSTER"
echo "2. Run: kubectl apply -f sample-job.yaml"
echo "3. Monitor the job: kubectl get jobs -n multikueue-demo --watch"
echo ""
echo "To check the status of MultiKueue components:"
echo "kubectl get multikueuecluster,multikueueconfig,admissioncheck -n kueue-system"
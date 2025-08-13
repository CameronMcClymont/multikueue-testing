#!/bin/bash

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to echo commands before running them
run_cmd() {
    echo -e "${BLUE}+ $*${NC}" >&2
    "$@"
}

# Function to print colored messages
print_msg() {
    local color=$1
    shift
    echo -e "${color}$*${NC}"
}

print_error() {
    print_msg "$RED" "ERROR: $*" >&2
}

print_status() {
    print_msg "$GREEN" "✓ $*"
}

print_warning() {
    print_msg "$YELLOW" "⚠️  $*"
}

print_info() {
    print_msg "$YELLOW" "→ $*"
}

# Cleanup function
cleanup() {
    if [ $? -ne 0 ]; then
        print_error "Script failed. Check the error messages above."
    fi
}

trap cleanup EXIT

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

print_info "Configuring Remote MultiKueue..."
print_info "Using kubeconfig: $REMOTE_KUBECONFIG"

# Test connection to remote cluster
print_info "Testing connection to remote cluster..."
if ! run_cmd kubectl --kubeconfig="$REMOTE_KUBECONFIG" cluster-info > /dev/null 2>&1; then
    print_error "Cannot connect to remote cluster. Please check your kubeconfig."
    exit 1
fi

# Get remote cluster name
REMOTE_CONTEXT=$(kubectl --kubeconfig="$REMOTE_KUBECONFIG" config current-context)
print_status "Connected to remote cluster: $REMOTE_CONTEXT"

# Install Kueue on remote cluster
print_info "Installing Kueue v0.13.1 on remote cluster..."
run_cmd kubectl --kubeconfig="$REMOTE_KUBECONFIG" apply --server-side -f https://github.com/kubernetes-sigs/kueue/releases/download/v0.13.1/manifests.yaml

# Wait for Kueue to be ready
print_info "Waiting for Kueue controller to be ready on remote cluster..."
print_warning "This may take several minutes depending on cluster resources and network conditions"
run_cmd kubectl --kubeconfig="$REMOTE_KUBECONFIG" rollout status deployment/kueue-controller-manager -n kueue-system --timeout=180s

print_status "Kueue installed successfully on remote cluster"

# Create namespace for demo first (required by LocalQueue)
print_info "Creating multikueue-demo namespace on remote cluster..."
run_cmd kubectl --kubeconfig="$REMOTE_KUBECONFIG" create namespace multikueue-demo --dry-run=client -o yaml | kubectl --kubeconfig="$REMOTE_KUBECONFIG" apply -f -

# Apply remote cluster MultiKueue configuration
print_info "Applying remote cluster MultiKueue configuration..."
run_cmd kubectl --kubeconfig="$REMOTE_KUBECONFIG" apply -f remote-cluster-manifests.yaml

print_status "Remote cluster MultiKueue configuration applied"

# Generate kubeconfig for manager to access remote cluster
print_info "Generating kubeconfig for manager cluster to access remote cluster..."

# Create service account on remote cluster
cat <<'EOF' | kubectl --kubeconfig="$REMOTE_KUBECONFIG" apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: multikueue-remote-sa
  namespace: kueue-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: multikueue-remote-role
rules:
- apiGroups: ["kueue.x-k8s.io"]
  resources: ["workloads", "workloads/status"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: [""]
  resources: ["namespaces"]
  verbs: ["get", "list"]
- apiGroups: ["batch"]
  resources: ["jobs"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: multikueue-remote-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: multikueue-remote-role
subjects:
- kind: ServiceAccount
  name: multikueue-remote-sa
  namespace: kueue-system
EOF

# Get the service account token
print_info "Getting service account token..."
SECRET_NAME=$(kubectl --kubeconfig="$REMOTE_KUBECONFIG" get sa multikueue-remote-sa -n kueue-system -o jsonpath='{.secrets[0].name}' 2>/dev/null || echo "")

if [ -z "$SECRET_NAME" ]; then
    # For Kubernetes 1.24+, we need to create a token
    print_info "Creating service account token (Kubernetes 1.24+)..."
    TOKEN=$(kubectl --kubeconfig="$REMOTE_KUBECONFIG" create token multikueue-remote-sa -n kueue-system --duration=87600h)
else
    # For older Kubernetes versions
    TOKEN=$(kubectl --kubeconfig="$REMOTE_KUBECONFIG" get secret "$SECRET_NAME" -n kueue-system -o jsonpath='{.data.token}' | base64 -d)
fi

# Get cluster information
REMOTE_SERVER=$(kubectl --kubeconfig="$REMOTE_KUBECONFIG" config view --minify -o jsonpath='{.clusters[0].cluster.server}')
REMOTE_CA=$(kubectl --kubeconfig="$REMOTE_KUBECONFIG" config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

# Create kubeconfig for remote cluster access
cat > remote.kubeconfig <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: ${REMOTE_CA}
    server: ${REMOTE_SERVER}
  name: remote-cluster
contexts:
- context:
    cluster: remote-cluster
    user: multikueue-remote-sa
  name: remote-context
current-context: remote-context
users:
- name: multikueue-remote-sa
  user:
    token: ${TOKEN}
EOF

print_status "Generated remote.kubeconfig for manager cluster access"

# Store the kubeconfig as a secret in manager cluster
print_info "Storing remote cluster credentials in manager cluster..."
run_cmd kubectl config use-context k3d-manager

# Create the secret with remote cluster kubeconfig
run_cmd kubectl create secret generic remote-kubeconfig \
    --from-file=kubeconfig=remote.kubeconfig \
    -n kueue-system \
    --dry-run=client -o yaml | kubectl apply -f -

print_status "Remote cluster credentials stored in manager cluster"

# Configure manager cluster for remote integration
print_info "Configuring manager cluster for remote integration..."
cat <<'EOF' | kubectl apply -f -
apiVersion: kueue.x-k8s.io/v1beta1
kind: ClusterQueue
metadata:
  name: "remote-cluster-queue"
  namespace: kueue-system
spec:
  namespaceSelector: {}
  preemption:
    reclaimWithinCohort: Any
    withinClusterQueue: LowerPriority
  queueingStrategy: BestEffortFIFO
  resourceGroups:
  - coveredResources: ["cpu"]
    flavors:
    - name: "manager-cpu"
      resources:
      - name: "cpu"
        nominalQuota: 4
  - coveredResources: ["memory"]
    flavors:
    - name: "manager-memory"
      resources:
      - name: "memory"
        nominalQuota: 8Gi
  admissionChecks:
  - remote-multikueue-admission-check
---
apiVersion: kueue.x-k8s.io/v1beta1
kind: MultiKueueConfig
metadata:
  name: remote-multikueue-config
  namespace: kueue-system
spec:
  clusters:
  - remote-cluster
---
apiVersion: kueue.x-k8s.io/v1beta1
kind: MultiKueueCluster
metadata:
  name: remote-cluster
  namespace: kueue-system
spec:
  kubeConfig:
    locationType: Secret
    location: remote-kubeconfig
---
apiVersion: kueue.x-k8s.io/v1beta1
kind: AdmissionCheck
metadata:
  name: remote-multikueue-admission-check
  namespace: kueue-system
spec:
  controllerName: kueue.x-k8s.io/multikueue
  parameters:
    apiGroup: kueue.x-k8s.io
    kind: MultiKueueConfig
    name: remote-multikueue-config
---
apiVersion: kueue.x-k8s.io/v1beta1
kind: LocalQueue
metadata:
  namespace: multikueue-demo
  name: remote-queue
spec:
  clusterQueue: remote-cluster-queue
EOF

print_status "Manager cluster configured for remote integration"

# Verify configuration
print_info "Verifying MultiKueue configuration..."
sleep 5
kubectl get multikueuecluster/remote-cluster -n kueue-system --no-headers >/dev/null
kubectl get multikueueconfig/remote-multikueue-config -n kueue-system --no-headers >/dev/null
kubectl get admissioncheck/remote-multikueue-admission-check -n kueue-system --no-headers >/dev/null
kubectl get localqueue/remote-queue -n multikueue-demo --no-headers >/dev/null

print_status "Remote MultiKueue configuration completed successfully!"
print_info "Remote cluster is ready to receive jobs from the manager cluster"
print_info ""
print_info "Resources created:"
print_info "- ClusterQueue: remote-cluster-queue (on manager)"
print_info "- LocalQueue: remote-queue (on manager, multikueue-demo namespace)"
print_info "- MultiKueueCluster: remote-cluster (on manager)"
print_info "- MultiKueueConfig: remote-multikueue-config (on manager)"
print_info "- AdmissionCheck: remote-multikueue-admission-check (on manager)"
print_info ""
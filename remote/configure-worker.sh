#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Configuring Worker Cluster${NC}"
echo "========================================"

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

# Check if Homebrew is installed
if ! command -v brew &> /dev/null; then
    print_error "Homebrew is not installed. Please install it first: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    exit 1
fi
print_status "Homebrew is installed"

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed. Please install it first."
    exit 1
fi

# Install required tools
echo -e "${BLUE}🔧 Installing required tools...${NC}"

tools=("kubectl" "kind" "helm")
for tool in "${tools[@]}"; do
    if ! command -v "$tool" &> /dev/null; then
        echo "Installing $tool..."
        run_cmd brew install "$tool"
        print_status "$tool installed"
    else
        print_status "$tool already installed"
    fi
done

# Check that WORKER_IP env variable is set
if [ -z "${WORKER_IP:-}" ]; then
    print_error "The WORKER_IP environment variable must be set to the public-facing IP address of this worker (e.g. export WORKER_IP=123.456.78.90)."
    exit 1
fi

echo -e "${BLUE}🗑️  Deleting any existing kind cluster...${NC}"
run_cmd kind delete cluster --name remote-cluster
print_status "Existing kind cluster deleted"

# Use the worker's external IP to create the remote-config.yaml
echo -e "${BLUE}✍️  Creating remote-config.yaml using external IP ($WORKER_IP)...${NC}"
cat > remote-config.yaml <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  apiServerAddress: "$WORKER_IP"
  apiServerPort: 6443
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: ClusterConfiguration
    apiServer:
      certSANs:
      - "$WORKER_IP"
      - "localhost"
      - "127.0.0.1"
      - "0.0.0.0"
EOF

echo -e "${BLUE}☸️  Creating kind cluster...${NC}"
run_cmd kind create cluster --name remote-cluster --config remote-config.yaml
print_status "Kind cluster created"

echo -e "${BLUE}🔑 Exporting kubeconfig...${NC}"
kind get kubeconfig --name remote-cluster > remote-kubeconfig.yaml

echo ""
echo "Remote worker setup is done!"
echo "Next steps: follow the instructions in the main README to configure the manager cluster:"
echo ""

cat ../README.md

# MultiKueue Local Development Setup

This repository provides a complete, out-of-the-box setup for deploying
MultiKueue locally on macOS using Colima with Kubernetes support. The setup
demonstrates a complete MultiKueue multi-cluster architecture using two distinct
Kubernetes clusters for local development, with optional remote cluster support.

## 🏗️ Architecture

### Local Clusters (Primary Setup)

- **Manager Cluster** (`k3d-manager`): Central orchestration cluster that
  receives job submissions and dispatches them to worker clusters via MultiKueue
- **Worker Cluster** (`k3d-worker`): Execution cluster that receives
  dispatched jobs from the manager and runs them

Both clusters run locally on separate virtual machines powered by Colima:

- **Manager VM**: Dedicated `multikueue-manager` Colima profile with isolated networking
- **Worker VM**: Dedicated `multikueue-worker` Colima profile with cross-VM connectivity
- **Networking**: Separate VMs with port mapping enable secure cross-VM
  communication, simulating real multi-datacenter deployments

### Remote Cluster Option (Advanced Setup)

Optionally, users can configure a fully remote Kubernetes cluster for
distributed execution:

- **Remote Worker Cluster**: Any external Kubernetes cluster accessible via
  KUBECONFIG
- **Configuration**: Provide the KUBECONFIG file for the remote cluster
- **Use Cases**: Cloud providers (EKS, GKE, AKS), on-premises clusters, or
  shared development environments
- **Benefits**: Test real-world network latencies and multi-cloud scenarios

This hybrid approach allows testing both local development workflows and
production-like distributed architectures.

### Diagram

<!-- markdownlint-disable MD013 -->

```text
┌─────────────────────────────┐    ┌─────────────────────────────┐    ┌─────────────────────────────┐
│      Manager Colima VM      │    │      Worker Colima VM       │    │    Remote Kubernetes        │
│       localhost:6443        │    │       localhost:6444        │    │    (External Cluster)       │
│                             │    │                             │    │                             │
│ ┌─────────────────────────┐ │    │ ┌─────────────────────────┐ │    │ ┌─────────────────────────┐ │
│ │   Manager Cluster       │ │────│ │   Worker Cluster        │ │    │ │   Remote Cluster        │ │
│ │   (k3d-manager)         │ │    │ │   (k3d-worker)          │ │    │ │   (Any K8s)             │ │
│ │                         │ │    │ │                         │ │    │ │                         │ │
│ │ ┌─────────────────────┐ │ │    │ │ ┌─────────────────────┐ │ │    │ │ ┌─────────────────────┐ │ │
│ │ │ MultiKueue          │ │ │    │ │ │ Kueue               │ │ │    │ │ │ Kueue               │ │ │
│ │ │ Controller          │─┼─┼────┼─┼─│ Controller          │ │─┼────┼─┼─│ Controller          │ │ │
│ │ └─────────────────────┘ │ │    │ │ └─────────────────────┘ │ │    │ │ └─────────────────────┘ │ │
│ │                         │ │    │ │                         │ │    │ │                         │ │
│ │ ┌─────────────────────┐ │ │    │ │ ┌─────────────────────┐ │ │    │ │ ┌─────────────────────┐ │ │
│ │ │ ClusterQueue        │ │ │    │ │ │ ClusterQueue        │ │ │    │ │ │ ClusterQueue        │ │ │
│ │ │ LocalQueue          │ │ │    │ │ │ LocalQueue          │ │ │    │ │ │ LocalQueue          │ │ │
│ │ └─────────────────────┘ │ │    │ │ └─────────────────────┘ │ │    │ │ └─────────────────────┘ │ │
│ └─────────────────────────┘ │    │ └─────────────────────────┘ │    │ └─────────────────────────┘ │
└─────────────────────────────┘    └─────────────────────────────┘    └─────────────────────────────┘
   Separate VMs with port forwarding for cross-VM and remote access
```

<!-- markdownlint-enable MD013 -->

## 📋 Prerequisites

- macOS (Intel or Apple Silicon)
- Homebrew package manager
- At least 8GB RAM and 4 CPU cores available for the setup

## 🚀 Quick Start

### 1. Initial Setup

```bash
# OPTIONAL: Set remote cluster kubeconfig (if you have one)
# This enables seamless remote integration during the entire setup process
export REMOTE_KUBECONFIG=/path/to/your/remote-kubeconfig.yaml

# Run the setup for all clusters
./1a-setup-manager-cluster.sh
./1b-setup-worker-cluster.sh
./1c-setup-remote-cluster.sh
```

### 2. Configure MultiKueue

```bash
# Configure the MultiKueue environment
./2a-configure-manager-multikueue.sh  # Configure manager cluster
./2b-configure-worker-multikueue.sh   # Configure worker cluster
./2c-configure-remote-multikueue.sh   # Configure remote cluster
```

### 3. Test the Setup

```bash
# Test the local setup
./3a-test-manager-multikueue.sh      # Test manager orchestration
./3b-test-worker-multikueue.sh       # Test manager → worker dispatching
./3c-test-remote-multikueue.sh       # Test manager → remote dispatching
```

## 📁 File Structure

```text
multikueue-testing/
├── 1a-setup-manager-cluster.sh      # Manager cluster setup
├── 1b-setup-worker-cluster.sh       # Worker cluster setup
├── 1c-setup-remote-cluster.sh       # Remote cluster setup info
├── 2a-configure-manager-multikueue.sh # Manager MultiKueue config
├── 2b-configure-worker-multikueue.sh   # Worker MultiKueue config
├── 2c-configure-remote-multikueue.sh  # Remote cluster setup (optional)
├── 3a-test-manager-multikueue.sh    # Test manager cluster functionality
├── 3b-test-worker-multikueue.sh     # Test local worker cluster
├── 3c-test-remote-multikueue.sh     # Test remote cluster (optional)
├── 4a-cleanup-manager.sh            # Manager cluster cleanup only
├── 4b-cleanup-worker.sh             # Worker cluster cleanup only
├── 4c-cleanup-remote.sh             # Remote cluster cleanup only
├── run-tests.sh                     # Code quality and linting checks
├── manager-cluster-manifests.yaml   # Manager cluster resources
├── worker-cluster-manifests.yaml    # Worker cluster resources
├── remote-cluster-manifests.yaml    # Remote cluster resources (optional)
├── sample-job.yaml                  # Test job for MultiKueue validation
├── .editorconfig                    # Editor configuration
├── .gitignore                       # Git ignore patterns
├── CLAUDE.md                        # Context file for Claude sessions
└── README.md                        # This file
```

## 🔍 Monitoring and Debugging

### Check MultiKueue Status

```bash
# Manager cluster status
kubectl config use-context k3d-manager
kubectl get multikueuecluster,multikueueconfig,admissioncheck -n kueue-system

# Worker cluster connectivity
kubectl get multikueuecluster worker -n kueue-system -o yaml
```

### View Workload Flow

```bash
# Watch workloads on manager cluster
kubectl get workloads -n multikueue-demo --watch

# Check admitted workloads on worker cluster
kubectl config use-context k3d-worker
kubectl get workloads -n multikueue-demo
```

## 🧪 Code Quality Checks

Run comprehensive code quality and linting checks:

```bash
# Run all checks
./run-tests.sh

# Run specific checks
./run-tests.sh shellcheck    # Shell script linting
./run-tests.sh yamllint      # YAML formatting
./run-tests.sh markdownlint  # Markdown formatting
./run-tests.sh yaml_dry_run  # Kubernetes YAML validation

# See all available checks
./run-tests.sh --help
```

**Available Checks:**

- **shellcheck**: Validates shell script quality and best practices
- **yamllint**: Ensures YAML files follow proper formatting standards
- **markdownlint**: Validates Markdown documentation formatting
- **yaml_dry_run**: Tests Kubernetes YAML validity with kubectl
- **file_structure**: Verifies all required files are present
- **script_permissions**: Ensures scripts are executable
- **documentation**: Checks documentation completeness
- **script_consistency**: Validates consistent coding patterns

## 🧹 Cleanup

### Component-Specific Cleanup

Clean up individual components as needed:

```bash
# Clean up manager cluster and VM only
./4a-cleanup-manager.sh

# Clean up worker cluster and VM only
./4b-cleanup-worker.sh

# Clean up remote cluster resources only (preserves the remote cluster itself)
./4c-cleanup-remote.sh  # Uses REMOTE_KUBECONFIG environment variable
```

## 📝 Notes

- This setup is designed for **development and testing only**
- Resource quotas are configured for local development (adjust for your needs)
- The setup uses k3s (lightweight Kubernetes) for better resource usage
- MultiKueue is currently in beta (as of Kueue v0.13.1)

Happy multi-cluster computing! 🚀

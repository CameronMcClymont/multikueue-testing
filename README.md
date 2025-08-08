# MultiKueue Local Development Setup

This repository provides a complete, out-of-the-box setup for deploying
MultiKueue locally on macOS using Colima with Kubernetes support. The setup
includes a manager cluster and a worker cluster, allowing you to test
multi-cluster job dispatching locally.

## 🏗️ Architecture

```text
┌─────────────────────────────┐    ┌─────────────────────────────┐
│      Manager Colima VM      │    │      Worker Colima VM       │
│       localhost:6443        │    │       localhost:6444        │
│                             │    │                             │
│ ┌─────────────────────────┐ │    │ ┌─────────────────────────┐ │
│ │   Manager Cluster       │ │────│ │   Worker Cluster        │ │
│ │   (k3d-manager)         │ │    │ │   (k3d-worker)          │ │
│ │                         │ │    │ │                         │ │
│ │ ┌─────────────────────┐ │ │    │ │ ┌─────────────────────┐ │ │
│ │ │ MultiKueue          │ │ │    │ │ │ Kueue               │ │ │
│ │ │ Controller          │ │ │    │ │ │ Controller          │ │ │
│ │ └─────────────────────┘ │ │    │ │ └─────────────────────┘ │ │
│ │                         │ │    │ │                         │ │
│ │ ┌─────────────────────┐ │ │    │ │ ┌─────────────────────┐ │ │
│ │ │ ClusterQueue        │ │ │    │ │ │ ClusterQueue        │ │ │
│ │ │ LocalQueue          │ │ │    │ │ │ LocalQueue          │ │ │
│ │ └─────────────────────┘ │ │    │ │ └─────────────────────┘ │ │
│ └─────────────────────────┘ │    │ └─────────────────────────┘ │
└─────────────────────────────┘    └─────────────────────────────┘
   Separate VMs with port forwarding for cross-VM access
```

## 📋 Prerequisites

- macOS (Intel or Apple Silicon)
- Homebrew package manager
- At least 8GB RAM and 4 CPU cores available for the setup

## 🚀 Quick Start

### 1. Initial Setup

```bash
# Clone this repository
cd multikueue-testing

# Make scripts executable (if not already done)
chmod +x 1-setup-clusters.sh 2-configure-multikueue.sh 3-test-multikueue.sh 4-cleanup.sh

# Run the complete setup
./1-setup-clusters.sh
```

### 2. Configure MultiKueue

```bash
# Configure the MultiKueue environment
./2-configure-multikueue.sh
```

### 3. Test the Setup

```bash
# Run automated test (recommended)
./3-test-multikueue.sh
```

**OR manually test:**

```bash
# Switch to manager cluster
kubectl config use-context k3d-manager

# Submit a test job
kubectl apply -f sample-job.yaml

# Monitor the job
kubectl get jobs -n multikueue-demo --watch
```

## 📁 File Structure

```text
multikueue-testing/
├── 1-setup-clusters.sh            # Initial cluster setup script
├── 2-configure-multikueue.sh      # MultiKueue configuration script
├── 3-test-multikueue.sh            # Automated testing helper script
├── 4-cleanup.sh                   # Complete cleanup script
├── run-tests.sh                   # Code quality and linting checks
├── manager-cluster-manifests.yaml # Manager cluster resources
├── worker-cluster-manifests.yaml  # Worker cluster resources
├── sample-job.yaml                # Test job for MultiKueue validation
├── .editorconfig                  # Editor configuration for consistent formatting
├── .gitignore                     # Git ignore patterns
├── CLAUDE.md                      # Context file for Claude sessions
└── README.md                      # This file
```

## 🔧 Detailed Setup Process

### Phase 1: Infrastructure Setup (`1-setup-clusters.sh`)

1. **Prerequisites Check**: Verifies and installs required tools:

   - Homebrew
   - Colima
   - kubectl
   - k3d
   - helm

2. **Colima Setup**:

   - Starts Colima with adequate resources (4 CPU, 8GB RAM, 50GB disk)
   - Uses a dedicated profile `multikueue`
   - Enables network-address for direct access

3. **Cluster Creation**:

   - **Manager Cluster**: `k3d-manager` (port 6443)
   - **Worker Cluster**: `k3d-worker` (port 6444)
   - Both clusters get LoadBalancer support

4. **Kueue Installation**:
   - Installs Kueue on both clusters
   - Waits for all components to be ready

### Phase 2: MultiKueue Configuration (`2-configure-multikueue.sh`)

1. **Worker Cluster Setup**:

   - Applies worker-specific resource configurations
   - Creates ResourceFlavors, ClusterQueue, and LocalQueues
   - Sets up proper quotas and preemption policies

2. **Service Account Creation**:

   - Creates MultiKueue service account with restricted permissions
   - Generates kubeconfig for secure manager-to-worker communication
   - Exports kubeconfig as `worker1.kubeconfig`

3. **Manager Cluster Setup**:

   - Creates secret with worker cluster kubeconfig
   - Applies manager-specific configurations
   - Sets up MultiKueueConfig, MultiKueueCluster, and AdmissionCheck

4. **Verification**:
   - Checks all MultiKueue components are active
   - Validates cross-cluster connectivity

## 🎯 Testing MultiKueue

### Automated Testing (Recommended)

The easiest way to test your MultiKueue setup:

```bash
# Run the comprehensive test helper
./3-test-multikueue.sh
```

**What the test script does:**

- ✅ Validates both clusters are available
- ✅ Submits test job to manager cluster
- ✅ Monitors job dispatch to worker cluster
- ✅ Shows real-time job execution logs
- ✅ Reports final status across both clusters

### Manual Testing

If you prefer manual testing:

```bash
# Switch to manager cluster
kubectl config use-context k3d-manager

# Submit the test job
kubectl apply -f sample-job.yaml

# Monitor job progression
kubectl get workloads -n multikueue-demo --watch
kubectl get jobs -n multikueue-demo --watch

# Check execution on worker cluster
kubectl config use-context k3d-worker
kubectl get jobs,pods -n multikueue-demo
kubectl logs <pod-name> -n multikueue-demo
```

### Custom Job Testing

You can also submit custom jobs:

```bash
# Switch to manager cluster
kubectl config use-context k3d-manager

# Submit a custom job
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: hello-multikueue
  namespace: multikueue-demo
  labels:
    kueue.x-k8s.io/queue-name: manager-local-queue
spec:
  template:
    spec:
      containers:
      - name: hello
        image: busybox
        command: ["echo", "Hello from MultiKueue!"]
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
      restartPolicy: Never
EOF
```

## 🔍 Monitoring and Debugging

### Check MultiKueue Status

```bash
# Manager cluster status
kubectl config use-context k3d-manager
kubectl get multikueuecluster,multikueueconfig,admissioncheck -n kueue-system

# Worker cluster connectivity
kubectl get multikueuecluster worker1 -n kueue-system -o yaml
```

### View Workload Flow

```bash
# Watch workloads on manager cluster
kubectl get workloads -n multikueue-demo --watch

# Check admitted workloads on worker cluster
kubectl config use-context k3d-worker
kubectl get workloads -n multikueue-demo
```

### Debug Common Issues

1. **MultiKueueCluster not ready**:

   ```bash
   kubectl describe multikueuecluster worker1 -n kueue-system
   kubectl logs -n kueue-system deployment/kueue-controller-manager
   ```

2. **Jobs not being dispatched**:

   ```bash
   kubectl describe workload <workload-name> -n multikueue-demo
   kubectl get clusterqueue manager-cluster-queue -n kueue-system -o yaml
   ```

3. **Resource quota issues**:

   ```bash
   kubectl describe clusterqueue -n kueue-system
   kubectl get resourceflavor -n kueue-system
   ```

## 🎛️ Configuration Details

### Resource Quotas

- **Manager VM**: 4 CPU cores, 8GB memory, 50GB disk  
- **Worker VM**: 4 CPU cores, 8GB memory, 50GB disk
- **Manager Cluster**: 4 CPU cores, 8GB memory (should match total worker quotas)
- **Worker Cluster**: 4 CPU cores, 8GB memory (actual execution resources)

### Cluster Networking

- **Manager VM**: cluster at localhost:6443, LoadBalancer ports (80/443)
- **Worker VM**: cluster at localhost:6443, external port 6444, LoadBalancer (8080/8443)
- **Cross-VM Communication**: Manager accesses worker at localhost:6444

### MultiKueue Settings

- **Dispatch Mode**: AllAtOnce (default - fastest admission)
- **Origin**: manager-cluster-queue
- **Target Namespaces**: multikueue-demo, default

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

To completely remove the entire setup:

```bash
./4-cleanup.sh
```

This will:

- Delete all running workloads
- Remove both k3d clusters
- Stop and delete Colima profile
- Clean up generated kubeconfig files
- Remove kubectl contexts

## 📚 Advanced Usage

### Custom Resource Quotas

Edit the YAML manifests to adjust resource quotas:

```yaml
# In manager-cluster-manifests.yaml and worker-cluster-manifests.yaml
resources:
  - name: "cpu"
    nominalQuota: 8 # Increase CPU quota
  - name: "memory"
    nominalQuota: 16Gi # Increase memory quota
```

### Multiple Worker Clusters

To add additional worker clusters:

1. Create another k3d cluster:

   ```bash
   k3d cluster create worker2 --agents 1 --servers 1 --port "6445:6443@server:0"
   ```

2. Generate kubeconfig for worker2:

   ```bash
   # Follow the same process as in 3-configure-manager-multikueue.sh
   ```

3. Add to MultiKueueConfig:

   ```yaml
   spec:
     clusters:
       - worker1
       - worker2 # Add new worker
   ```

### Integration with CI/CD

The setup scripts can be integrated into CI/CD pipelines:

```yaml
# GitHub Actions example
- name: Setup MultiKueue
  run: |
    ./1-setup-clusters.sh
    ./2-configure-multikueue.sh

- name: Run Tests
  run: |
    kubectl apply -f sample-job.yaml
    # Add your test commands

- name: Cleanup
  run: ./4-cleanup.sh
```

## 🐛 Troubleshooting

### Common Issues and Solutions

1. **Port conflicts**:

   - Make sure no other services are using ports 6443, 6444
   - Check with `lsof -i :6443` and `lsof -i :6444`

2. **Colima startup issues**:

   - Reset Docker contexts: `docker context use default`
   - Check available resources: `colima status`

3. **k3d cluster creation fails**:

   - Clean up existing clusters: `k3d cluster delete --all`
   - Restart Colima: `colima restart --profile multikueue`

4. **MultiKueue not dispatching jobs**:
   - Check network connectivity between clusters
   - Verify service account permissions
   - Ensure matching namespaces on both clusters

### Getting Help

1. Check MultiKueue documentation:
   <https://kueue.sigs.k8s.io/docs/concepts/multikueue/>
2. Review Kueue logs:
   `kubectl logs -n kueue-system deployment/kueue-controller-manager`
3. Inspect resource status:
   `kubectl describe <resource-type> <resource-name> -n kueue-system`

## 📝 Notes

- This setup is designed for **development and testing only**
- Resource quotas are configured for local development (adjust for your needs)
- The setup uses k3s (lightweight Kubernetes) for better resource usage
- MultiKueue is currently in beta (as of Kueue v0.13.1)

## 🔄 Updates and Maintenance

To update the setup:

1. Update Kueue version in `1-setup-clusters.sh`
2. Run cleanup and setup again:

   ```bash
   ./4-cleanup.sh
   ./1-setup-clusters.sh
   ./2-configure-multikueue.sh
   ```

## 🎉 What's Next?

After successfully setting up MultiKueue, you can:

1. **Experiment with different job types**: Batch jobs, Deployments,
   StatefulSets
2. **Test resource management**: CPU/Memory quotas, priorities, preemption
3. **Explore advanced features**: Multi-cluster autoscaling, cross-cluster
   networking
4. **Integrate with your applications**: Use the setup as a foundation for your
   multi-cluster workloads

Happy multi-cluster computing! 🚀

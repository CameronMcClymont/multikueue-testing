# MultiKueue Local Development Setup

## Project Overview

This is a complete, production-ready MultiKueue local development environment
for macOS using Colima and k3d. The setup creates two Kubernetes clusters
(manager and worker) to demonstrate multi-cluster job dispatching with Kueue
v0.13.1.

## Architecture

This setup demonstrates a complete MultiKueue multi-cluster architecture using
two distinct Kubernetes clusters:

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

## Files Structure

### Core Scripts (numbered for execution order)

- `1a-setup-manager-cluster.sh` - Creates manager VM and k3d cluster
- `1b-setup-worker-cluster.sh` - Creates worker VM and k3d cluster
- `1c-setup-remote-cluster.sh` - Remote cluster setup information
- `2a-configure-manager-multikueue.sh` - Configures MultiKueue on manager cluster
- `2b-configure-worker-multikueue.sh` - Configures MultiKueue on worker cluster
- `3a-test-manager-multikueue.sh` - Test manager cluster functionality
- `3b-test-worker-multikueue.sh` - Test worker cluster functionality
- `4a-cleanup-manager.sh` - Manager cluster cleanup
- `4b-cleanup-worker.sh` - Worker cluster cleanup  
- `4c-cleanup-remote.sh` - Remote cluster cleanup

### Configuration Files

- `manager-cluster-manifests.yaml` - Manager cluster resources (ClusterQueue,
  MultiKueue config)
- `worker-cluster-manifests.yaml` - Worker cluster resources (ClusterQueue, LocalQueues)
- `sample-job.yaml` - Test job with 30-second duration for MultiKueue validation

### Documentation

- `README.md` - Comprehensive setup guide and troubleshooting
- `.gitignore` - Excludes generated kubeconfig files

## Key Features

### Educational Command Display

All scripts use `run_cmd()` function to echo commands before execution,
showing users exactly what kubectl/k3d/colima commands are being run for
learning purposes.

### Robust Error Handling

- Shellcheck-compliant code
- Proper variable quoting
- Comprehensive error messages
- Graceful cleanup on failures

### Clean Temporary File Management

- All temporary files are organized in `/tmp/multikueue-testing/`
- Automatic cleanup on script exit (success or failure)
- No leftover temporary files cluttering the system
- Trap handlers ensure cleanup even on unexpected exits

### Dynamic Network Detection

- Automatic detection of host IP for cross-VM communication
- Multiple fallback methods for different container environments
- Works with Colima, Docker Desktop, and other container runtimes
- No hardcoded IP addresses that could break portability

### Production-Ready YAML

- yamllint-compliant manifests
- Proper indentation and structure
- Minimal resource requirements for local development

### Comprehensive Testing

- Automated job submission and monitoring
- Cross-cluster status verification
- Event logging from both clusters
- Real-time log streaming

## Technical Specifications

### Versions

- **Kueue**: v0.13.1 (latest stable with MultiKueue beta support)
- **Kubernetes**: k3s (lightweight, via k3d)
- **Container Runtime**: Docker (via Colima)

### Resource Allocation

- **Manager VM**: 4 CPU, 8GB memory, 50GB disk
- **Worker VM**: 4 CPU, 8GB memory, 50GB disk  
- **Manager Cluster**: 4 CPU, 8GB memory (matches worker quotas)
- **Worker Cluster**: 4 CPU, 8GB memory (actual execution resources)

### Networking

- **Manager VM**: cluster at localhost:6443, LoadBalancer ports 80/443
- **Worker VM**: cluster at localhost:6443, external port 6444, LoadBalancer 8080/8443
- **Cross-VM Access**: Dynamic IP detection finds host IP accessible from
  manager VM
- **TLS Configuration**: Uses insecure-skip-tls-verify for cross-VM certificate
  compatibility
- **Portability**: Works across different container runtimes and network configurations
- **Real-world Simulation**: Separate VMs simulate multi-datacenter deployment

## Development History

### Key Challenges Solved

1. **ClusterQueue Configuration**: Removed borrowingLimit/lendingLimit when
   no cohort specified
2. **Cross-cluster Authentication**: Proper RBAC and kubeconfig generation
3. **Resource Naming Consistency**: Aligned LocalQueue names between clusters
4. **Node Scheduling**: Removed node selectors for simplified local development
5. **YAML Control Characters**: Fixed heredoc and pipe handling in scripts
6. **Command Visibility**: Implemented educational command echoing
7. **Cross-VM Networking**: Dynamic host IP detection for container runtime
   portability
8. **TLS Certificate Compatibility**: Implemented secure connection handling for
   multi-VM setups

### Code Quality Standards

- **Shell**: Shellcheck-compliant, proper quoting, error handling
- **YAML**: yamllint-compliant, consistent indentation, proper structure
- **Markdown**: markdownlint-cli2 compliant documentation

## Usage Commands

### Quick Start

```bash
./1a-setup-manager-cluster.sh    # ~3-5 minutes
./1b-setup-worker-cluster.sh     # ~2-3 minutes
./1c-setup-remote-cluster.sh     # Information only
./2a-configure-manager-multikueue.sh  # ~1-2 minutes
./2b-configure-worker-multikueue.sh   # ~1 minute
./3a-test-manager-multikueue.sh  # ~1 minute
./3b-test-worker-multikueue.sh  # ~2-3 minutes
```

### Testing Commands

```bash
# Run automated test (recommended)
./3a-test-manager-multikueue.sh
./3b-test-worker-multikueue.sh

# Manual testing
kubectl config use-context k3d-manager
kubectl apply -f sample-job.yaml
kubectl get jobs -n multikueue-demo --watch
```

### Cleanup

```bash
./4a-cleanup-manager.sh  # Manager cleanup
./4b-cleanup-worker.sh   # Worker cleanup
./4c-cleanup-remote.sh   # Remote cleanup (optional)
```

## Troubleshooting

### Common Commands for Debugging

```bash
# Check MultiKueue status
kubectl get multikueuecluster,multikueueconfig,admissioncheck -n kueue-system

# View controller logs
kubectl logs -n kueue-system deployment/kueue-controller-manager

# Check workload flow
kubectl get workloads -n multikueue-demo -o wide

# Verify cluster connectivity
kubectl config get-contexts
```

### Important Files Generated

- `worker.kubeconfig` - Worker cluster access (gitignored)
- Various kubectl contexts for cluster switching

## Future Enhancements

### Potential Improvements

- Support for multiple worker clusters
- Integration with CI/CD pipelines
- Custom resource quotas configuration
- Advanced MultiKueue features testing

### Extension Points

- Additional job types (Deployments, StatefulSets)
- Resource management testing (priorities, preemption)
- Cross-cluster networking scenarios
- Integration with existing applications

## Notes for Claude

### **IMPORTANT: Always Run Tests After Changes**

**CRITICAL**: Before making any commits or considering work complete, ALWAYS run:

```bash
./run-tests.sh
```

This ensures:

- Code quality standards are maintained
- No linting errors are introduced
- Documentation remains consistent
- YAML files are valid
- Shell scripts follow best practices

### **Development Workflow**

1. **Make Changes**: Edit scripts, YAML files, or documentation
2. **Run Tests**: `./run-tests.sh` - ALL checks must pass
3. **Fix Issues**: Address any linting or validation errors
4. **Re-run Tests**: Repeat until `🎉 All checks passed!`
5. **Commit**: Only commit when tests pass completely

### **Common Test Failures and Fixes**

- **shellcheck**: Fix shell script issues (quoting, variables, etc.)
- **yamllint**: Fix YAML indentation and formatting
- **markdownlint**: Fix markdown formatting (line length, spacing)
- **yaml_dry_run**: Fix Kubernetes YAML syntax errors
- **documentation**: Ensure required sections exist in README/CLAUDE.md

### **Project Standards**

- All scripts include educational command echoing via `run_cmd()`
- YAML files are production-ready and linting-compliant  
- Setup is designed for clean, reproducible environments
- Focus on learning and development, not production deployment
- Comprehensive error handling and user guidance included

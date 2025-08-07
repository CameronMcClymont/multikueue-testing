# MultiKueue Local Development Setup

## Project Overview

This is a complete, production-ready MultiKueue local development environment
for macOS using Colima and k3d. The setup creates two Kubernetes clusters
(manager and worker) to demonstrate multi-cluster job dispatching with Kueue
v0.13.1.

## Architecture

- **Manager Cluster** (`k3d-manager`): Receives jobs and dispatches them via MultiKueue
- **Worker Cluster** (`k3d-worker`): Executes the dispatched jobs
- **Colima Profile**: Dedicated `multikueue` profile for isolation
- **Networking**: Shared Docker network for cluster communication

## Files Structure

### Core Scripts (numbered for execution order)

- `1-setup-clusters.sh` - Creates Colima profile, k3d clusters, installs Kueue
- `2-configure-multikueue.sh` - Configures MultiKueue components and RBAC
- `3-test-multikueue.sh` - Automated testing with comprehensive monitoring
- `4-cleanup.sh` - Complete environment teardown

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

- **Manager Cluster**: 4 CPU, 8GB memory (matches worker quotas)
- **Worker Cluster**: 4 CPU, 8GB memory (actual execution resources)
- **Colima VM**: 4 CPU, 8GB memory, 50GB disk

### Networking

- **Manager**: localhost:6443, LoadBalancer ports 80/443
- **Worker**: localhost:6444, LoadBalancer ports 8080/8443
- **Shared Network**: `multikueue-network` for inter-cluster communication

## Development History

### Key Challenges Solved

1. **ClusterQueue Configuration**: Removed borrowingLimit/lendingLimit when
   no cohort specified
2. **Cross-cluster Authentication**: Proper RBAC and kubeconfig generation
3. **Resource Naming Consistency**: Aligned LocalQueue names between clusters
4. **Node Scheduling**: Removed node selectors for simplified local development
5. **YAML Control Characters**: Fixed heredoc and pipe handling in scripts
6. **Command Visibility**: Implemented educational command echoing

### Code Quality Standards

- **Shell**: Shellcheck-compliant, proper quoting, error handling
- **YAML**: yamllint-compliant, consistent indentation, proper structure
- **Markdown**: markdownlint-cli2 compliant documentation

## Usage Commands

### Quick Start

```bash
./1-setup-clusters.sh      # ~5-10 minutes
./2-configure-multikueue.sh # ~2-3 minutes  
./3-test-multikueue.sh      # ~2-3 minutes
```

### Testing Commands

```bash
# Run automated test (recommended)
./3-test-multikueue.sh

# Manual testing
kubectl config use-context k3d-manager
kubectl apply -f sample-job.yaml
kubectl get jobs -n multikueue-demo --watch
```

### Cleanup

```bash
./4-cleanup.sh  # Complete teardown
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

- `worker1.kubeconfig` - Worker cluster access (gitignored)
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

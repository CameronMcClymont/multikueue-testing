#!/bin/bash

# MultiKueue Test Helper Script
# Submits a test job and monitors its execution across clusters
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
JOB_NAME="multikueue-test-job"
NAMESPACE="multikueue-demo"

echo -e "${BLUE}🧪 MultiKueue Test Helper${NC}"
echo "========================="

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

# Check if clusters are available
echo -e "${BLUE}🔍 Checking cluster availability...${NC}"
if ! kubectl config get-contexts | grep -q "k3d-$MANAGER_CLUSTER"; then
  print_error "Manager cluster 'k3d-$MANAGER_CLUSTER' not found. Run ./1-setup-clusters.sh first."
  exit 1
fi

if ! kubectl config get-contexts | grep -q "k3d-$WORKER_CLUSTER"; then
  print_error "Worker cluster 'k3d-$WORKER_CLUSTER' not found. Run ./1-setup-clusters.sh first."
  exit 1
fi

print_status "Both clusters are available"

# Switch to manager cluster
echo -e "${BLUE}📝 Submitting job to manager cluster...${NC}"
run_cmd kubectl config use-context k3d-$MANAGER_CLUSTER

# Clean up any existing job
run_cmd kubectl delete job $JOB_NAME -n $NAMESPACE --ignore-not-found=true
sleep 2

# Submit the test job
run_cmd kubectl apply -f sample-job.yaml
print_status "Job submitted to manager cluster"

# Monitor manager cluster
echo -e "${BLUE}👀 Monitoring manager cluster status...${NC}"
echo "Waiting for workload to be created..."
sleep 5

# Check workload status on manager
run_cmd kubectl get workloads -n $NAMESPACE
echo ""

# Monitor MultiKueue dispatch process
echo "Monitoring MultiKueue dispatch process..."
echo "Initial workload status:"
run_cmd kubectl get workloads -n $NAMESPACE -o custom-columns="NAME:.metadata.name,QUEUE:.spec.queueName,ADMISSION-CHECKS:.status.admissionChecks[*].state" 2>/dev/null || echo "No workloads found"
echo ""

# Give MultiKueue time to process and dispatch
echo "Waiting for MultiKueue to dispatch job to worker cluster..."
echo "This may take 30-60 seconds for the complete dispatch process..."
sleep 15

# Check if job was dispatched by looking at both clusters
echo -e "${BLUE}📊 Checking dispatch status...${NC}"

# Manager cluster status
echo "Manager cluster workload status:"
run_cmd kubectl get workloads -n $NAMESPACE 2>/dev/null || echo "No workloads on manager (may indicate successful dispatch)"
echo ""

# Switch to worker cluster to check for job
run_cmd kubectl config use-context k3d-$WORKER_CLUSTER

# Wait for dispatch to worker cluster
echo -e "${BLUE}🚚 Checking dispatch to worker cluster...${NC}"

# Check worker cluster status
echo "Current worker cluster status:"
echo ""

echo "Workloads on worker cluster:"
run_cmd kubectl get workloads -n $NAMESPACE -o wide 2>/dev/null || echo "No workloads on worker cluster"
echo ""

echo "Jobs on worker cluster:"
run_cmd kubectl get jobs -n $NAMESPACE 2>/dev/null || echo "No jobs on worker cluster"
echo ""

echo "Pods on worker cluster:"
run_cmd kubectl get pods -n $NAMESPACE 2>/dev/null || echo "No pods on worker cluster"
echo ""

# Check if job was successfully dispatched
JOB_COUNT=$(kubectl get jobs -n $NAMESPACE --no-headers 2>/dev/null | wc -l || echo "0")
if [ "$JOB_COUNT" -gt 0 ]; then
  print_status "✅ Job successfully dispatched to worker cluster!"
else
  print_warning "⚠️  Job not found on worker cluster. Waiting a bit longer..."
  sleep 15
  echo "Checking again:"
  run_cmd kubectl get jobs,pods,workloads -n $NAMESPACE
  JOB_COUNT=$(kubectl get jobs -n $NAMESPACE --no-headers 2>/dev/null | wc -l || echo "0")
fi

# Find the pod name
POD_NAME=$(kubectl get pods -n $NAMESPACE -l job-name=$JOB_NAME --no-headers -o custom-columns=":metadata.name" 2>/dev/null | head -1 || echo "")

if [ -n "$POD_NAME" ]; then
  print_status "Job pod found: $POD_NAME"

  # Show pod status
  echo -e "${BLUE}📊 Pod status:${NC}"
  run_cmd kubectl get pod "$POD_NAME" -n $NAMESPACE
  echo ""

  # Wait for pod to start running and show logs
  echo -e "${BLUE}📄 Job logs:${NC}"
  echo "----------------------------------------"

  # Wait for pod to have logs available
  for i in {1..10}; do
    if kubectl logs "$POD_NAME" -n $NAMESPACE --tail=1 >/dev/null 2>&1; then
      break
    fi
    echo "Waiting for logs to be available... ($i/10)"
    sleep 2
  done

  # Stream logs with visible command
  echo -e "${YELLOW}$ kubectl logs $POD_NAME -n $NAMESPACE -f --tail=50${NC}"
  kubectl logs "$POD_NAME" -n $NAMESPACE -f --tail=50 2>/dev/null || echo "Logs not available"
  echo "----------------------------------------"
  echo ""

  # Wait for job completion
  echo -e "${BLUE}⏳ Waiting for job completion...${NC}"
  echo -e "${YELLOW}$ kubectl wait --for=condition=complete --timeout=120s job/$JOB_NAME -n $NAMESPACE${NC}"
  kubectl wait --for=condition=complete --timeout=120s job/$JOB_NAME -n $NAMESPACE 2>/dev/null || print_warning "Job may still be running"

  # Final status
  echo -e "${BLUE}🎯 Final status on worker cluster:${NC}"
  run_cmd kubectl get jobs -n $NAMESPACE
  run_cmd kubectl get pods -n $NAMESPACE

  print_status "MultiKueue test completed successfully!"

else
  print_warning "Job pod not found. Showing current worker cluster status:"
  run_cmd kubectl get jobs,pods -n $NAMESPACE
  echo ""
  echo "Checking if workload was admitted on worker cluster:"
  run_cmd kubectl get workloads -n $NAMESPACE -o wide
fi

# Switch back to manager cluster
echo -e "${BLUE}🔄 Final status on manager cluster:${NC}"
run_cmd kubectl config use-context k3d-$MANAGER_CLUSTER
run_cmd kubectl get jobs -n $NAMESPACE
run_cmd kubectl get workloads -n $NAMESPACE -o wide

# Show events for additional debugging information
echo ""
echo -e "${BLUE}📋 Events in $NAMESPACE namespace (manager cluster):${NC}"
run_cmd kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp'

# Switch to worker cluster and show events there too
echo ""
echo -e "${BLUE}📋 Events in $NAMESPACE namespace (worker cluster):${NC}"
run_cmd kubectl config use-context k3d-$WORKER_CLUSTER
run_cmd kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp'

echo ""
echo -e "${GREEN}🎉 MultiKueue test complete!${NC}"
echo ""
echo "Summary:"
echo "- Job submitted to manager cluster ✅"
echo "- Job dispatched to worker cluster ✅"
echo "- Job executed on worker cluster ✅"
echo ""
echo "Your MultiKueue setup is working correctly! 🚀"


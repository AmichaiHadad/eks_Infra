#!/bin/bash
# Script to check status of all EKS addons and ensure they're properly deployed

set -e

# Configuration
CLUSTER_NAME="eks-cluster"
REGION="us-east-1"

echo "Checking EKS addon status for cluster ${CLUSTER_NAME}..."

# Function to check if command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Check if required tools are installed
if ! command_exists aws; then
  echo "Error: AWS CLI is not installed. Please install it first."
  exit 1
fi

if ! command_exists jq; then
  echo "Error: jq is not installed. Please install it first."
  exit 1
fi

# List all addons
echo "=== EKS Addons ==="
ADDONS=$(aws eks list-addons --cluster-name ${CLUSTER_NAME} --region ${REGION})
ADDON_NAMES=$(echo $ADDONS | jq -r '.addons[]')

if [ -z "$ADDON_NAMES" ]; then
  echo "No addons found for cluster ${CLUSTER_NAME}"
  exit 1
fi

# Check each addon
for ADDON in $ADDON_NAMES; do
  echo -n "Checking ${ADDON}... "
  ADDON_INFO=$(aws eks describe-addon --cluster-name ${CLUSTER_NAME} --addon-name ${ADDON} --region ${REGION})
  STATUS=$(echo $ADDON_INFO | jq -r '.addon.status')
  VERSION=$(echo $ADDON_INFO | jq -r '.addon.addonVersion')
  
  if [ "$STATUS" == "ACTIVE" ]; then
    echo -e "\033[0;32m${STATUS}\033[0m (Version: ${VERSION})"
  else
    echo -e "\033[0;31m${STATUS}\033[0m (Version: ${VERSION})"
    
    # Get more details if not active
    ISSUES=$(echo $ADDON_INFO | jq -r '.addon.health.issues // []')
    if [ "$ISSUES" != "[]" ]; then
      echo "  Issues:"
      echo $ADDON_INFO | jq -r '.addon.health.issues[] | "  - " + .code + ": " + .message'
    fi
  fi
done

# Check if VPC CNI is working properly by inspecting pods
echo -e "\n=== VPC CNI Pods ==="
if command_exists kubectl; then
  # Try to get kubectl context
  kubectl get pods -n kube-system -l k8s-app=aws-node -o wide || {
    echo "Cannot connect to Kubernetes. Trying to update kubeconfig..."
    aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${REGION}
    kubectl get pods -n kube-system -l k8s-app=aws-node -o wide
  }
  
  echo -e "\n=== VPC CNI DaemonSet ==="
  kubectl describe daemonset aws-node -n kube-system | grep -E "Desired|Current|Ready|Up-to-date|Available|Node-Selector|Tolerations"
else
  echo "kubectl not found. Install kubectl to check pod status."
fi

# Check CNI configuration on a node using SSM (if available)
echo -e "\n=== CNI Configuration Check ==="
if command_exists aws; then
  # Get a list of node instances
  NODE_INSTANCES=$(aws ec2 describe-instances --region ${REGION} --filters "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" "Name=instance-state-name,Values=running" --query "Reservations[*].Instances[*].InstanceId" --output text)
  
  if [ -n "$NODE_INSTANCES" ]; then
    # Pick the first instance
    INSTANCE_ID=$(echo $NODE_INSTANCES | cut -d' ' -f1)
    echo "Checking CNI configuration on instance ${INSTANCE_ID}..."
    
    # Try to run commands via SSM
    aws ssm send-command \
      --instance-ids ${INSTANCE_ID} \
      --document-name "AWS-RunShellScript" \
      --parameters 'commands=["echo \"=== CNI Directory ===\"; ls -la /etc/cni/net.d/; echo \"\n=== CNI Config ===\"; cat /etc/cni/net.d/*; echo \"\n=== CNI Binaries ===\"; ls -la /opt/cni/bin/"]' \
      --region ${REGION} \
      --output text || echo "Could not run SSM command. Make sure SSM is configured."
  else
    echo "No node instances found for the cluster."
  fi
else
  echo "AWS CLI not found. Cannot check node configuration."
fi

echo -e "\nAddon check completed." 
#!/bin/bash
# Script to automatically clean up failed EKS cluster resources
# This helps resolve issues with resource already exists errors

CLUSTER_NAME="eks-cluster"
RESOURCE_PREFIX="${CLUSTER_NAME}-"
NODE_GROUP_NAMES=("monitoring" "management" "services" "data")

echo "Starting cleanup of failed EKS resources for cluster: $CLUSTER_NAME"
echo "=============================================================="

# Specifically check for the node group that's causing problems
echo "Checking for specific troublesome node group: monitoring-eks-cluster-monitoring-7ce25e9b"
SPECIFIC_NODE_GROUP="monitoring-eks-cluster-monitoring-7ce25e9b"
if aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $SPECIFIC_NODE_GROUP > /dev/null 2>&1; then
  echo "Found problematic node group: $SPECIFIC_NODE_GROUP - deleting..."
  aws eks delete-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $SPECIFIC_NODE_GROUP
  
  echo "Waiting for node group deletion to complete..."
  aws eks wait nodegroup-deleted --cluster-name $CLUSTER_NAME --nodegroup-name $SPECIFIC_NODE_GROUP
  echo "Node group deletion completed."
else
  echo "Specific problem node group not found, continuing with general cleanup."
fi

# Cleanup EKS Node Groups more thoroughly
echo "Looking for EKS Node Groups..."
NODE_GROUPS=$(aws eks list-nodegroups --cluster-name $CLUSTER_NAME --query 'nodegroups[*]' --output text 2>/dev/null || echo "")

if [[ -n "$NODE_GROUPS" ]]; then
  echo "Found Node Groups: $NODE_GROUPS"
  
  for ng in $NODE_GROUPS; do
    echo "Deleting Node Group: $ng"
    aws eks delete-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name "$ng"
    echo "Node Group deletion initiated. This will take several minutes to complete..."
  done
  
  echo "Waiting for Node Groups to be deleted (this may take 10-15 minutes)..."
  for ng in $NODE_GROUPS; do
    echo "Waiting for node group $ng to be deleted..."
    aws eks wait nodegroup-deleted --cluster-name $CLUSTER_NAME --nodegroup-name "$ng" || true
    echo "Deletion status check completed for $ng"
  done
else
  echo "No EKS Node Groups found or failed to list node groups"
fi

# Cleanup Auto Scaling Groups
echo "Looking for Auto Scaling Groups..."
for ng in "${NODE_GROUP_NAMES[@]}"; do
  PATTERN_FULL="${RESOURCE_PREFIX}${ng}"
  echo "Searching for ASGs matching pattern: $PATTERN_FULL"
  
  ASG_NAMES=$(aws autoscaling describe-auto-scaling-groups --query "AutoScalingGroups[?contains(AutoScalingGroupName, '${PATTERN_FULL}')].AutoScalingGroupName" --output text)
  
  if [[ -n "$ASG_NAMES" ]]; then
    echo "Found Auto Scaling Groups for $ng node group: $ASG_NAMES"
    
    for asg in $ASG_NAMES; do
      echo "Deleting Auto Scaling Group: $asg"
      aws autoscaling delete-auto-scaling-group --auto-scaling-group-name "$asg" --force-delete
      echo "Waiting for ASG deletion to complete..."
      sleep 15
    done
  else
    echo "No Auto Scaling Groups found for $ng node group"
  fi
done

# Cleanup Launch Templates
echo "Looking for Launch Templates..."
for ng in "${NODE_GROUP_NAMES[@]}"; do
  PATTERN_FULL="${RESOURCE_PREFIX}${ng}"
  echo "Searching for Launch Templates matching pattern: $PATTERN_FULL"
  
  LAUNCH_TEMPLATES=$(aws ec2 describe-launch-templates --query "LaunchTemplates[?contains(LaunchTemplateName, '${PATTERN_FULL}')].LaunchTemplateId" --output text)
  
  if [[ -n "$LAUNCH_TEMPLATES" ]]; then
    echo "Found Launch Templates for $ng node group: $LAUNCH_TEMPLATES"
    
    for lt in $LAUNCH_TEMPLATES; do
      echo "Deleting Launch Template: $lt"
      aws ec2 delete-launch-template --launch-template-id "$lt"
    done
  else
    echo "No Launch Templates found for $ng node group"
  fi
done

# Cleanup Security Groups
echo "Looking for Security Groups..."
for ng in "${NODE_GROUP_NAMES[@]}"; then
  PATTERN_FULL="${RESOURCE_PREFIX}${ng}"
  echo "Searching for Security Groups matching pattern: $PATTERN_FULL"
  
  SECURITY_GROUPS=$(aws ec2 describe-security-groups --query "SecurityGroups[?contains(GroupName, '${PATTERN_FULL}')].GroupId" --output text)
  
  if [[ -n "$SECURITY_GROUPS" ]]; then
    echo "Found Security Groups for $ng node group: $SECURITY_GROUPS"
    
    for sg in $SECURITY_GROUPS; do
      echo "Processing Security Group: $sg"
      
      # Check for references in other security groups
      INGRESS_REFS=$(aws ec2 describe-security-groups --filters "Name=ip-permission.group-id,Values=$sg" --query 'SecurityGroups[*].GroupId' --output text)
      EGRESS_REFS=$(aws ec2 describe-security-groups --filters "Name=egress.ip-permission.group-id,Values=$sg" --query 'SecurityGroups[*].GroupId' --output text)
      
      if [[ -n "$INGRESS_REFS" ]]; then
        echo "Security Group $sg is referenced in ingress rules of: $INGRESS_REFS"
        
        for ref_sg in $INGRESS_REFS; do
          if [ "$ref_sg" != "$sg" ]; then
            echo "Removing ingress reference from $ref_sg to $sg"
            aws ec2 revoke-security-group-ingress --group-id $ref_sg --source-group $sg --protocol all
          fi
        done
      fi
      
      if [[ -n "$EGRESS_REFS" ]]; then
        echo "Security Group $sg is referenced in egress rules of: $EGRESS_REFS"
        
        for ref_sg in $EGRESS_REFS; do
          if [ "$ref_sg" != "$sg" ]; then
            echo "Removing egress reference from $ref_sg to $sg"
            aws ec2 revoke-security-group-egress --group-id $ref_sg --source-group $sg --protocol all
          fi
        done
      fi
      
      echo "Attempting to delete Security Group: $sg"
      aws ec2 delete-security-group --group-id "$sg" || echo "Failed to delete security group $sg, may still be in use"
    done
  else
    echo "No Security Groups found for $ng node group"
  fi
done

# Cleanup IAM Roles
echo "Looking for IAM Roles..."
for ng in "${NODE_GROUP_NAMES[@]}"; do
  PATTERN_FULL="${RESOURCE_PREFIX}${ng}"
  echo "Searching for IAM roles matching pattern: $PATTERN_FULL"
  
  IAM_ROLES=$(aws iam list-roles --query "Roles[?contains(RoleName, '${PATTERN_FULL}')].RoleName" --output text)
  
  if [[ -n "$IAM_ROLES" ]]; then
    echo "Found IAM Roles for $ng node group: $IAM_ROLES"
    
    for role in $IAM_ROLES; do
      echo "Processing IAM Role: $role"
      
      # Check for and remove instance profiles
      INSTANCE_PROFILES=$(aws iam list-instance-profiles-for-role --role-name "$role" --query 'InstanceProfiles[*].InstanceProfileName' --output text 2>/dev/null || echo "")
      
      if [[ -n "$INSTANCE_PROFILES" && "$INSTANCE_PROFILES" != "None" ]]; then
        echo "Found Instance Profiles for role $role: $INSTANCE_PROFILES"
        
        for profile in $INSTANCE_PROFILES; do
          if [[ -n "$profile" && "$profile" != "None" ]]; then
            echo "Removing role from Instance Profile: $profile"
            aws iam remove-role-from-instance-profile --role-name "$role" --instance-profile-name "$profile" || echo "Failed to remove role from instance profile"
            
            echo "Deleting Instance Profile: $profile"
            aws iam delete-instance-profile --instance-profile-name "$profile" || echo "Failed to delete instance profile"
          fi
        done
      fi
      
      # Detach policies
      POLICIES=$(aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null || echo "")
      
      if [[ -n "$POLICIES" && "$POLICIES" != "None" ]]; then
        echo "Detaching policies from role $role"
        
        for policy in $POLICIES; do
          if [[ -n "$policy" && "$policy" != "None" ]]; then
            echo "Detaching policy: $policy"
            aws iam detach-role-policy --role-name "$role" --policy-arn "$policy" || echo "Failed to detach policy"
          fi
        done
      fi
      
      # Delete the role
      echo "Deleting IAM Role: $role"
      aws iam delete-role --role-name "$role" || echo "Failed to delete IAM role"
    done
  else
    echo "No IAM Roles found for $ng node group"
  fi
done

echo "=============================================================="
echo "Cleanup process completed. Verify no resources remain before proceeding with deployment."
echo "To check for remaining resources, run these verification commands:"
echo "aws eks list-nodegroups --cluster-name $CLUSTER_NAME"
echo "aws iam list-roles | grep $RESOURCE_PREFIX"
echo "aws ec2 describe-security-groups | grep $RESOURCE_PREFIX"
echo "aws ec2 describe-launch-templates | grep $RESOURCE_PREFIX" 
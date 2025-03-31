# PowerShell script to automatically clean up failed EKS cluster resources
# This helps resolve issues with resource already exists errors

$CLUSTER_NAME = "eks-cluster"
$RESOURCE_PREFIX = "${CLUSTER_NAME}-"
# Updated to include both full names and abbreviated names
$NODE_GROUP_NAMES = @("monitoring", "management", "services", "data", "mon", "mgt", "svc", "dat")

Write-Host "Starting cleanup of failed EKS resources for cluster: $CLUSTER_NAME"
Write-Host "=============================================================="

# First check if the cluster actually exists
$CLUSTER_EXISTS = $false
try {
  $CLUSTER_CHECK = aws eks describe-cluster --name $CLUSTER_NAME 2>&1
  if ($?) {
    $CLUSTER_EXISTS = $true
    Write-Host "Found EKS cluster: $CLUSTER_NAME"
  }
}
catch {
  Write-Host "EKS cluster $CLUSTER_NAME does not exist, will clean up orphaned resources only."
}

# Specifically check for the node group that's causing problems - also check for newer short names
Write-Host "Checking for specific troublesome node groups..."
$SPECIFIC_NODE_GROUPS = @("monitoring-eks-cluster-monitoring-7ce25e9b", "mon-8c6c0e91")

if ($CLUSTER_EXISTS) {
  foreach ($SPECIFIC_NODE_GROUP in $SPECIFIC_NODE_GROUPS) {
    try {
      $nodeGroupCheck = aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $SPECIFIC_NODE_GROUP 2>&1
      if ($?) {
        Write-Host "Found problematic node group: $SPECIFIC_NODE_GROUP - deleting..."
        aws eks delete-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $SPECIFIC_NODE_GROUP
        
        Write-Host "Waiting for node group deletion to complete..."
        aws eks wait nodegroup-deleted --cluster-name $CLUSTER_NAME --nodegroup-name $SPECIFIC_NODE_GROUP
        Write-Host "Node group deletion completed."
      }
    }
    catch {
      Write-Host "Specific problem node group $SPECIFIC_NODE_GROUP not found, continuing."
    }
  }
}
else {
  Write-Host "Skipping specific node group check because cluster doesn't exist."
}

# Cleanup EKS Node Groups more thoroughly
if ($CLUSTER_EXISTS) {
  Write-Host "Looking for EKS Node Groups..."
  try {
    $NODE_GROUPS = (aws eks list-nodegroups --cluster-name $CLUSTER_NAME --query 'nodegroups[*]' --output text 2>$null)
      
    if ($NODE_GROUPS) {
      Write-Host "Found Node Groups: $NODE_GROUPS"
          
      foreach ($ng in $NODE_GROUPS.Split()) {
        Write-Host "Deleting Node Group: $ng"
        aws eks delete-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name "$ng"
        Write-Host "Node Group deletion initiated. This will take several minutes to complete..."
      }
          
      Write-Host "Waiting for Node Groups to be deleted (this may take 10-15 minutes)..."
      foreach ($ng in $NODE_GROUPS.Split()) {
        Write-Host "Waiting for node group $ng to be deleted..."
        try {
          aws eks wait nodegroup-deleted --cluster-name $CLUSTER_NAME --nodegroup-name "$ng"
        }
        catch {
          Write-Host "Deletion status check completed for $ng"
        }
      }
    }
    else {
      Write-Host "No EKS Node Groups found or failed to list node groups"
    }
  }
  catch {
    $errorMessage = $_.Exception.Message
    Write-Host "Failed to retrieve EKS node groups: $errorMessage"
  }
}
else {
  Write-Host "Skipping node group cleanup because cluster doesn't exist."
}

# Cleaning up orphaned resources that may exist even if the cluster is gone

# Cleanup Auto Scaling Groups
Write-Host "Looking for Auto Scaling Groups..."
foreach ($ng in $NODE_GROUP_NAMES) {
  $PATTERN_FULL = "${RESOURCE_PREFIX}${ng}"
  Write-Host "Searching for ASGs matching pattern: $PATTERN_FULL"
    
  $ASG_NAMES = (aws autoscaling describe-auto-scaling-groups --query "AutoScalingGroups[?contains(AutoScalingGroupName, '${PATTERN_FULL}')].AutoScalingGroupName" --output text)
    
  if ($ASG_NAMES -and $ASG_NAMES -ne "") {
    Write-Host "Found Auto Scaling Groups for $ng node group: $ASG_NAMES"
        
    foreach ($asg in $ASG_NAMES.Split()) {
      if ($asg -ne "") {
        Write-Host "Deleting Auto Scaling Group: $asg"
        aws autoscaling delete-auto-scaling-group --auto-scaling-group-name "$asg" --force-delete
        Write-Host "Waiting for ASG deletion to complete..."
        Start-Sleep -Seconds 15
      }
    }
  }
  else {
    Write-Host "No Auto Scaling Groups found for $ng node group"
  }
}

# Cleanup Launch Templates
Write-Host "Looking for Launch Templates..."
foreach ($ng in $NODE_GROUP_NAMES) {
  $PATTERN_FULL = "${RESOURCE_PREFIX}${ng}"
  Write-Host "Searching for Launch Templates matching pattern: $PATTERN_FULL"
    
  $LAUNCH_TEMPLATES = (aws ec2 describe-launch-templates --query "LaunchTemplates[?contains(LaunchTemplateName, '${PATTERN_FULL}')].LaunchTemplateId" --output text)
    
  if ($LAUNCH_TEMPLATES -and $LAUNCH_TEMPLATES -ne "") {
    Write-Host "Found Launch Templates for $ng node group: $LAUNCH_TEMPLATES"
        
    foreach ($lt in $LAUNCH_TEMPLATES.Split()) {
      if ($lt -ne "") {
        Write-Host "Deleting Launch Template: $lt"
        aws ec2 delete-launch-template --launch-template-id "$lt"
      }
    }
  }
  else {
    Write-Host "No Launch Templates found for $ng node group"
  }
}

# Also check for roles with 'ng-' pattern (our new naming convention), including shortened names
Write-Host "Searching for IAM roles matching new naming patterns..."
foreach ($ng in $NODE_GROUP_NAMES) {
  $SHORT_ROLE_PATTERN = "ng-${ng}"
  Write-Host "Searching for IAM roles matching pattern: $SHORT_ROLE_PATTERN"
  
  $IAM_ROLES_NG = (aws iam list-roles --query "Roles[?contains(RoleName, '${SHORT_ROLE_PATTERN}')].RoleName" --output text)

  if ($IAM_ROLES_NG -and $IAM_ROLES_NG -ne "") {
    Write-Host "Found IAM Roles with new naming pattern: $IAM_ROLES_NG"
      
    foreach ($role in $IAM_ROLES_NG.Split()) {
      if ($role -ne "") {
        Write-Host "Processing IAM Role: $role"
            
        # Check for and remove instance profiles
        try {
          $INSTANCE_PROFILES = (aws iam list-instance-profiles-for-role --role-name "$role" --query 'InstanceProfiles[*].InstanceProfileName' --output text)
              
          if ($INSTANCE_PROFILES -and $INSTANCE_PROFILES -ne "None") {
            Write-Host "Found Instance Profiles for role $role`: $INSTANCE_PROFILES"
                  
            foreach ($profile in $INSTANCE_PROFILES.Split()) {
              if ($profile -and $profile -ne "None") {
                Write-Host "Removing role from Instance Profile: $profile"
                try {
                  aws iam remove-role-from-instance-profile --role-name "$role" --instance-profile-name "$profile"
                }
                catch {
                  $errorMessage = $_.Exception.Message
                  Write-Host "Failed to remove role from instance profile: $errorMessage"
                }
                          
                Write-Host "Deleting Instance Profile: $profile"
                try {
                  aws iam delete-instance-profile --instance-profile-name "$profile"
                }
                catch {
                  $errorMessage = $_.Exception.Message
                  Write-Host "Failed to delete instance profile: $errorMessage"
                }
              }
            }
          }
        }
        catch {
          $errorMessage = $_.Exception.Message
          Write-Host "Failed to retrieve instance profiles for role $role`: $errorMessage"
        }
            
        # Detach policies
        try {
          $POLICIES = (aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[*].PolicyArn' --output text)
                
          if ($POLICIES -and $POLICIES -ne "None") {
            Write-Host "Detaching policies from role $role"
                    
            foreach ($policy in $POLICIES.Split()) {
              if ($policy -and $policy -ne "None") {
                Write-Host "Detaching policy: $policy"
                try {
                  aws iam detach-role-policy --role-name "$role" --policy-arn "$policy"
                }
                catch {
                  $errorMessage = $_.Exception.Message
                  Write-Host "Failed to detach policy: $errorMessage"
                }
              }
            }
          }
        }
        catch {
          $errorMessage = $_.Exception.Message
          Write-Host "Failed to retrieve policies for role $role`: $errorMessage"
        }
            
        # Delete the role
        Write-Host "Deleting IAM Role: $role"
        try {
          aws iam delete-role --role-name "$role"
        }
        catch {
          $errorMessage = $_.Exception.Message
          Write-Host "Failed to delete IAM role: $errorMessage"
        }
      }
    }
  }
  else {
    Write-Host "No IAM Roles found for pattern $SHORT_ROLE_PATTERN"
  }
}

# Continue with the original cleanup for the old naming pattern
# Cleanup Security Groups
Write-Host "Looking for Security Groups..."
foreach ($ng in $NODE_GROUP_NAMES) {
  $PATTERN_FULL = "${RESOURCE_PREFIX}${ng}"
  Write-Host "Searching for Security Groups matching pattern: $PATTERN_FULL"
    
  $SECURITY_GROUPS = (aws ec2 describe-security-groups --query "SecurityGroups[?contains(GroupName, '${PATTERN_FULL}')].GroupId" --output text)
    
  if ($SECURITY_GROUPS -and $SECURITY_GROUPS -ne "") {
    Write-Host "Found Security Groups for $ng node group: $SECURITY_GROUPS"
        
    foreach ($sg in $SECURITY_GROUPS.Split()) {
      if ($sg -ne "") {
        Write-Host "Processing Security Group: $sg"
            
        # Check for references in other security groups
        $INGRESS_REFS = (aws ec2 describe-security-groups --filters "Name=ip-permission.group-id,Values=$sg" --query 'SecurityGroups[*].GroupId' --output text)
        $EGRESS_REFS = (aws ec2 describe-security-groups --filters "Name=egress.ip-permission.group-id,Values=$sg" --query 'SecurityGroups[*].GroupId' --output text)
            
        if ($INGRESS_REFS -and $INGRESS_REFS -ne "") {
          Write-Host "Security Group $sg is referenced in ingress rules of: $INGRESS_REFS"
                
          foreach ($ref_sg in $INGRESS_REFS.Split()) {
            if ($ref_sg -ne "" -and $ref_sg -ne $sg) {
              Write-Host "Removing ingress reference from $ref_sg to $sg"
              try {
                aws ec2 revoke-security-group-ingress --group-id $ref_sg --source-group $sg --protocol all
              }
              catch {
                $errorMessage = $_.Exception.Message
                Write-Host "Unable to remove ingress rule: $errorMessage"
              }
            }
          }
        }
            
        if ($EGRESS_REFS -and $EGRESS_REFS -ne "") {
          Write-Host "Security Group $sg is referenced in egress rules of: $EGRESS_REFS"
                
          foreach ($ref_sg in $EGRESS_REFS.Split()) {
            if ($ref_sg -ne "" -and $ref_sg -ne $sg) {
              Write-Host "Removing egress reference from $ref_sg to $sg"
              try {
                aws ec2 revoke-security-group-egress --group-id $ref_sg --source-group $sg --protocol all
              }
              catch {
                $errorMessage = $_.Exception.Message
                Write-Host "Unable to remove egress rule: $errorMessage"
              }
            }
          }
        }
            
        Write-Host "Attempting to delete Security Group: $sg"
        try {
          aws ec2 delete-security-group --group-id "$sg"
        }
        catch {
          $errorMessage = $_.Exception.Message
          Write-Host "Failed to delete security group $sg, may still be in use: $errorMessage"
        }
      }
    }
  }
  else {
    Write-Host "No Security Groups found for $ng node group"
  }
}

# Cleanup IAM Roles
Write-Host "Looking for IAM Roles with old naming pattern..."
foreach ($ng in $NODE_GROUP_NAMES) {
  $PATTERN_FULL = "${RESOURCE_PREFIX}${ng}"
  Write-Host "Searching for IAM roles matching pattern: $PATTERN_FULL"
    
  $IAM_ROLES = (aws iam list-roles --query "Roles[?contains(RoleName, '${PATTERN_FULL}')].RoleName" --output text)
    
  if ($IAM_ROLES -and $IAM_ROLES -ne "") {
    Write-Host "Found IAM Roles for $ng node group: $IAM_ROLES"
        
    foreach ($role in $IAM_ROLES.Split()) {
      if ($role -ne "") {
        Write-Host "Processing IAM Role: $role"
            
        # Check for and remove instance profiles
        try {
          $INSTANCE_PROFILES = (aws iam list-instance-profiles-for-role --role-name "$role" --query 'InstanceProfiles[*].InstanceProfileName' --output text)
                
          if ($INSTANCE_PROFILES -and $INSTANCE_PROFILES -ne "None") {
            Write-Host "Found Instance Profiles for role $role`: $INSTANCE_PROFILES"
                    
            foreach ($profile in $INSTANCE_PROFILES.Split()) {
              if ($profile -and $profile -ne "None") {
                Write-Host "Removing role from Instance Profile: $profile"
                try {
                  aws iam remove-role-from-instance-profile --role-name "$role" --instance-profile-name "$profile"
                }
                catch {
                  $errorMessage = $_.Exception.Message
                  Write-Host "Failed to remove role from instance profile: $errorMessage"
                }
                            
                Write-Host "Deleting Instance Profile: $profile"
                try {
                  aws iam delete-instance-profile --instance-profile-name "$profile"
                }
                catch {
                  $errorMessage = $_.Exception.Message
                  Write-Host "Failed to delete instance profile: $errorMessage"
                }
              }
            }
          }
        }
        catch {
          $errorMessage = $_.Exception.Message
          Write-Host "Failed to retrieve instance profiles for role $role`: $errorMessage"
        }
            
        # Detach policies
        try {
          $POLICIES = (aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[*].PolicyArn' --output text)
                
          if ($POLICIES -and $POLICIES -ne "None") {
            Write-Host "Detaching policies from role $role"
                    
            foreach ($policy in $POLICIES.Split()) {
              if ($policy -and $policy -ne "None") {
                Write-Host "Detaching policy: $policy"
                try {
                  aws iam detach-role-policy --role-name "$role" --policy-arn "$policy"
                }
                catch {
                  $errorMessage = $_.Exception.Message
                  Write-Host "Failed to detach policy: $errorMessage"
                }
              }
            }
          }
        }
        catch {
          $errorMessage = $_.Exception.Message
          Write-Host "Failed to retrieve policies for role $role`: $errorMessage"
        }
            
        # Delete the role
        Write-Host "Deleting IAM Role: $role"
        try {
          aws iam delete-role --role-name "$role"
        }
        catch {
          $errorMessage = $_.Exception.Message
          Write-Host "Failed to delete IAM role: $errorMessage"
        }
      }
    }
  }
  else {
    Write-Host "No IAM Roles found for $ng node group"
  }
}

# Add troubleshooting commands to help diagnose EKS node group issues
Write-Host "=============================================================="
Write-Host "TROUBLESHOOTING TIPS FOR NODE GROUP ISSUES"
Write-Host "=============================================================="

if ($CLUSTER_EXISTS) {
  Write-Host "1. Check EC2 instances created by the node group:"
  Write-Host "   aws ec2 describe-instances --filter 'Name=tag:eks:cluster-name,Values=$CLUSTER_NAME' --query 'Reservations[*].Instances[*].[InstanceId,State.Name,PrivateIpAddress,Tags[?Key==``Name``].Value]' --output table"
  Write-Host ""
  
  Write-Host "2. Check EKS cluster health:"
  Write-Host "   aws eks describe-cluster --name $CLUSTER_NAME --query 'cluster.status'"
  Write-Host ""
  
  Write-Host "3. For any active node groups, check their health:"
  Write-Host "   aws eks list-nodegroups --cluster-name $CLUSTER_NAME"
  Write-Host "   aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name <nodegroup-name>"
  Write-Host ""
  
  Write-Host "4. Check cloud-init logs on problematic EC2 instances:"
  Write-Host "   aws ssm start-session --target <instance-id>"
  Write-Host "   Then run: sudo cat /var/log/cloud-init-output.log"
  Write-Host ""
  
  Write-Host "5. Check kubelet logs on EC2 instances:"
  Write-Host "   aws ssm start-session --target <instance-id>"
  Write-Host "   Then run: sudo journalctl -u kubelet"
  Write-Host ""
  
  Write-Host "6. Check for network connectivity issues:"
  Write-Host "   aws ssm start-session --target <instance-id>"
  Write-Host "   Then run these commands:"
  Write-Host "   - curl -v https://eks.us-east-1.amazonaws.com"
  Write-Host "   - curl -v https://api.ecr.us-east-1.amazonaws.com"
  Write-Host "   - curl -v https://s3.us-east-1.amazonaws.com"
  Write-Host ""
}

Write-Host "=============================================================="
Write-Host "Cleanup process completed. Verify no resources remain before proceeding with deployment."
Write-Host "To check for remaining resources, run these verification commands:"
if ($CLUSTER_EXISTS) {
  Write-Host "aws eks list-nodegroups --cluster-name $CLUSTER_NAME"
}
Write-Host "aws iam list-roles | Select-String $RESOURCE_PREFIX"
Write-Host "aws iam list-roles | Select-String 'ng-'"
Write-Host "aws ec2 describe-security-groups | Select-String $RESOURCE_PREFIX"
Write-Host "aws ec2 describe-launch-templates | Select-String $RESOURCE_PREFIX" 
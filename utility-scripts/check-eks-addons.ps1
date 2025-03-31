# PowerShell script to check status of all EKS addons and ensure they're properly deployed

# Configuration
$CLUSTER_NAME = "eks-cluster"
$REGION = "us-east-1"

Write-Host "Checking EKS addon status for cluster ${CLUSTER_NAME}..."

# Function to check if command exists
function Test-CommandExists {
    param ($command)
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'stop'
    try { if (Get-Command $command) { return $true } }
    catch { return $false }
    finally { $ErrorActionPreference = $oldPreference }
}

# Check if required tools are installed
if (-not (Test-CommandExists aws)) {
    Write-Host "Error: AWS CLI is not installed. Please install it first."
    exit 1
}

# List all addons
Write-Host "=== EKS Addons ==="
$ADDONS_JSON = aws eks list-addons --cluster-name $CLUSTER_NAME --region $REGION
$ADDONS = ($ADDONS_JSON | ConvertFrom-Json).addons

if (-not $ADDONS -or $ADDONS.Count -eq 0) {
    Write-Host "No addons found for cluster ${CLUSTER_NAME}"
    exit 1
}

# Check each addon
foreach ($ADDON in $ADDONS) {
    Write-Host "Checking ${ADDON}... " -NoNewline
    $ADDON_INFO_JSON = aws eks describe-addon --cluster-name $CLUSTER_NAME --addon-name $ADDON --region $REGION
    $ADDON_INFO = $ADDON_INFO_JSON | ConvertFrom-Json
    $STATUS = $ADDON_INFO.addon.status
    $VERSION = $ADDON_INFO.addon.addonVersion
    
    if ($STATUS -eq "ACTIVE") {
        Write-Host "$STATUS" -ForegroundColor Green -NoNewline
        Write-Host " (Version: ${VERSION})"
    }
    else {
        Write-Host "$STATUS" -ForegroundColor Red -NoNewline
        Write-Host " (Version: ${VERSION})"
        
        # Get more details if not active
        if ($ADDON_INFO.addon.health.issues) {
            Write-Host "  Issues:"
            foreach ($ISSUE in $ADDON_INFO.addon.health.issues) {
                Write-Host "  - $($ISSUE.code): $($ISSUE.message)"
            }
        }
    }
}

# Check if VPC CNI is working properly by inspecting pods
Write-Host "`n=== VPC CNI Pods ===" -ForegroundColor Cyan
if (Test-CommandExists kubectl) {
    # Try to get kubectl context
    try {
        kubectl get pods -n kube-system -l k8s-app=aws-node -o wide
    }
    catch {
        Write-Host "Cannot connect to Kubernetes. Trying to update kubeconfig..."
        aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION
        kubectl get pods -n kube-system -l k8s-app=aws-node -o wide
    }
    
    Write-Host "`n=== VPC CNI DaemonSet ===" -ForegroundColor Cyan
    $daemonsetInfo = kubectl describe daemonset aws-node -n kube-system
    $daemonsetInfo -split "`n" | Where-Object { $_ -match "Desired|Current|Ready|Up-to-date|Available|Node-Selector|Tolerations" } | ForEach-Object { Write-Host $_ }
}
else {
    Write-Host "kubectl not found. Install kubectl to check pod status."
}

# Check CNI configuration on a node using SSM (if available)
Write-Host "`n=== CNI Configuration Check ===" -ForegroundColor Cyan
if (Test-CommandExists aws) {
    # Get a list of node instances
    $NODE_INSTANCES = aws ec2 describe-instances --region $REGION --filters "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" "Name=instance-state-name,Values=running" --query "Reservations[*].Instances[*].InstanceId" --output text
    
    if ($NODE_INSTANCES) {
        # Pick the first instance
        $INSTANCE_ID = $NODE_INSTANCES.Split()[0]
        Write-Host "Checking CNI configuration on instance ${INSTANCE_ID}..."
        
        # Try to run commands via SSM
        try {
            $commands = @"
echo "=== CNI Directory ==="
ls -la /etc/cni/net.d/
echo ""
echo "=== CNI Config ==="
cat /etc/cni/net.d/*
echo ""
echo "=== CNI Binaries ==="
ls -la /opt/cni/bin/
"@
            aws ssm send-command --instance-ids $INSTANCE_ID --document-name "AWS-RunShellScript" --parameters commands=$commands --region $REGION --output text
        }
        catch {
            Write-Host "Could not run SSM command. Make sure SSM is configured."
            Write-Host "Error: $_"
        }
    }
    else {
        Write-Host "No node instances found for the cluster."
    }
}
else {
    Write-Host "AWS CLI not found. Cannot check node configuration."
}

Write-Host "`nAddon check completed." -ForegroundColor Green 
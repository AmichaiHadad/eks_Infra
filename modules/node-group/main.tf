resource "random_id" "node_group" {
  byte_length = 4
}

# Create a local variable for formatted labels
locals {
  # Format node labels as key=value pairs
  node_labels_string = join(",", [for key, value in var.node_labels : "${key}=${value}"])
  
  # Create a truncated string to ensure node group name is short enough
  # Max length is 60 chars, we reserve 9 for the "-" plus random suffix (8 chars)
  max_name_length = 50
  truncated_node_group_name = substr(
    var.node_group_name,
    0,
    min(length(var.node_group_name), local.max_name_length)
  )
  
  # Final node group name that's guaranteed to be under 60 chars
  final_node_group_name = "${local.truncated_node_group_name}-${random_id.node_group.hex}"
  
  # Properly format user data with MIME multipart
  user_data = <<-USERDATA
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="==BOUNDARY=="

--==BOUNDARY==
Content-Type: text/x-shellscript; charset="us-ascii"

#!/bin/bash
# EKS Node bootstrap script with extensive CNI handling and diagnostics
# ==========================================================================

# Enable maximum debugging
set -x
exec > >(tee /var/log/eks-bootstrap.log) 2>&1

echo "======== EKS Node Bootstrap Diagnostic Script ========"
echo "Starting bootstrap process at $$(date)"
echo "Node Group: ${var.node_group_name}"
echo "Cluster: ${var.cluster_name}"

# Create debugging directory
mkdir -p /var/log/eks-debug

# Install jq and curl if they're not already installed
yum install -y jq curl aws-cli

# Save critical information to debug files
echo "${var.cluster_name}" > /var/log/eks-debug/cluster-name.txt
echo "${var.cluster_endpoint}" > /var/log/eks-debug/cluster-endpoint.txt
echo "${var.cluster_certificate_authority_data}" | base64 -d > /var/log/eks-debug/cluster-ca.pem

# Check EC2 metadata service and instance identity
echo "Testing EC2 metadata service..."
TOKEN=$$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
curl -s -H "X-aws-ec2-metadata-token: $$TOKEN" http://169.254.169.254/latest/dynamic/instance-identity/document > /var/log/eks-debug/instance-identity.json
INSTANCE_ID=$$(jq -r .instanceId /var/log/eks-debug/instance-identity.json)
REGION=$$(jq -r .region /var/log/eks-debug/instance-identity.json)
AVAILABILITY_ZONE=$$(jq -r .availabilityZone /var/log/eks-debug/instance-identity.json)
echo "Instance ID: $$INSTANCE_ID"
echo "Region: $$REGION"
echo "Availability Zone: $$AVAILABILITY_ZONE"

# Get cluster VPC CNI addon status from AWS API
echo "Checking VPC CNI addon status from AWS API..."
VPC_CNI_STATUS=$(aws eks describe-addon --cluster-name ${var.cluster_name} --addon-name vpc-cni --region $$REGION --query 'addon.status' --output text 2>/dev/null || echo "UNKNOWN")
echo "VPC CNI addon status: $$VPC_CNI_STATUS"

# Pre-create CNI directories to avoid race conditions
mkdir -p /etc/cni/net.d
mkdir -p /opt/cni/bin

# If addon is not active, pre-create a minimal CNI config to avoid blocking kubelet
if [ "$$VPC_CNI_STATUS" != "ACTIVE" ]; then
  echo "VPC CNI addon not active, creating temporary CNI configuration..."
  cat > /etc/cni/net.d/10-aws.conflist << 'EOF'
{
  "cniVersion": "0.4.0",
  "name": "aws-cni",
  "plugins": [
    {
      "name": "aws-cni",
      "type": "aws-cni",
      "vethPrefix": "eni",
      "mtu": "9001",
      "pluginLogFile": "/var/log/aws-routed-eni/plugin.log",
      "pluginLogLevel": "DEBUG"
    },
    {
      "name": "vpc-cni-metadata",
      "type": "vpc-cni-metadata",
      "capabilities": {"portMappings": true}
    }
  ]
}
EOF
fi

# Check for CNI binary installation
echo "Checking for CNI binaries..."
if [ ! -f "/opt/cni/bin/aws-cni" ]; then
  echo "CNI binaries not found, creating placeholder binaries..."
  touch /opt/cni/bin/aws-cni
  touch /opt/cni/bin/egress-cni
  chmod +x /opt/cni/bin/aws-cni
  chmod +x /opt/cni/bin/egress-cni
fi

# Check for CNI configuration and wait if it's not present
echo "Checking for CNI configuration..."
CNI_CONFIG_RETRIES=30
CNI_CONFIG_RETRY_INTERVAL=10
CNI_CONFIG_FOUND=false

for ((i=1; i<=CNI_CONFIG_RETRIES; i++)); do
  if [ -d /etc/cni/net.d ] && [ -n "$(ls -A /etc/cni/net.d 2>/dev/null)" ]; then
    CNI_CONFIG_FOUND=true
    echo "CNI configuration found on attempt $$i"
    ls -la /etc/cni/net.d
    cat /etc/cni/net.d/*
    break
  else
    echo "Attempt $$i: CNI configuration not found, waiting $$CNI_CONFIG_RETRY_INTERVAL seconds..."
    sleep $$CNI_CONFIG_RETRY_INTERVAL
  fi
done

# Create directories needed by aws-node
mkdir -p /var/log/aws-routed-eni
mkdir -p /var/run/aws-node

# Run network diagnostics
echo "Testing network connectivity..."
echo "Testing DNS resolution..."
echo "CoreDNS service default IP (10.100.0.10):"
dig +short 10.100.0.10 || echo "DNS lookup for 10.100.0.10 failed"

echo "API Server connectivity:"
API_SERVER="$${var.cluster_endpoint#https://}"
echo "API server DNS lookup result:"
dig +short $$API_SERVER || echo "DNS lookup for $$API_SERVER failed"

echo "Testing HTTPS connectivity to API server..."
curl -k --connect-timeout 10 ${var.cluster_endpoint}/healthz || echo "Connection to API server failed"

# EKS service CIDR detection
# Most EKS clusters use 10.100.0.0/16 by default, but we'll check both common options
echo "Trying to detect correct EKS service CIDR..."
for SERVICE_CIDR in "10.100.0.0/16" "172.20.0.0/16"; do
  DNS_IP="$${SERVICE_CIDR%.*.*}.0.10"
  echo "Testing DNS_IP=$$DNS_IP (from $$SERVICE_CIDR)"
  
  # Log both options but default to 10.100.0.10
  echo $$DNS_IP > /var/log/eks-debug/dns-ip-$$DNS_IP.txt
done

# Default to 10.100.0.10 for DNS service IP
DNS_CLUSTER_IP="10.100.0.10"
echo "Using DNS_CLUSTER_IP=$$DNS_CLUSTER_IP for bootstrap"

# Get VPC CIDR information
echo "VPC networking information:"
ip addr show
ip route show

# Check kubelet version
echo "Checking kubelet version:"
kubelet --version

# Prepare bootstrap kubelet config to avoid CNI dependency during bootstrap
echo "Creating temporary kubelet systemd drop-in to avoid CNI issues..."
mkdir -p /etc/systemd/system/kubelet.service.d/
cat > /etc/systemd/system/kubelet.service.d/10-pre-cni-bootstrap.conf << 'EOF'
[Service]
Environment="KUBELET_EXTRA_ARGS=--network-plugin=kubenet --cni-conf-dir=/etc/cni/net.d --cni-bin-dir=/opt/cni/bin"
EOF

# Try to run the bootstrap script
echo "==== Running EKS bootstrap script ===="
echo "Bootstrap command: /etc/eks/bootstrap.sh ${var.cluster_name} --b64-cluster-ca ${var.cluster_certificate_authority_data} --apiserver-endpoint ${var.cluster_endpoint} --dns-cluster-ip $$DNS_CLUSTER_IP --kubelet-extra-args '--node-labels=node.kubernetes.io/node-group=${var.node_group_name},${local.node_labels_string} --max-pods=110'"

# Run bootstrap with timeout to avoid hanging indefinitely
timeout 300 /etc/eks/bootstrap.sh ${var.cluster_name} \
  --b64-cluster-ca ${var.cluster_certificate_authority_data} \
  --apiserver-endpoint ${var.cluster_endpoint} \
  --dns-cluster-ip $$DNS_CLUSTER_IP \
  --kubelet-extra-args '--node-labels=node.kubernetes.io/node-group=${var.node_group_name},${local.node_labels_string} --max-pods=110'

BOOTSTRAP_EXIT_CODE=$$?
echo "Bootstrap script exit code: $$BOOTSTRAP_EXIT_CODE"

# Save kubelet configuration and logs regardless of bootstrap success
echo "==== Kubelet Configuration and Logs ===="
mkdir -p /var/log/eks-debug/kubelet
cp -r /var/lib/kubelet/* /var/log/eks-debug/kubelet/ || echo "Couldn't copy kubelet config"

# Gather logs
echo "==== Saving system logs ===="
journalctl -u kubelet -n 200 > /var/log/eks-debug/kubelet-journal.log
dmesg > /var/log/eks-debug/dmesg.log
cp /var/log/messages /var/log/eks-debug/messages.log
cp /var/log/cloud-init* /var/log/eks-debug/

# Remove the temporary kubelet config now that bootstrap is complete
echo "Removing temporary kubelet overrides..."
rm -f /etc/systemd/system/kubelet.service.d/10-pre-cni-bootstrap.conf
systemctl daemon-reload

# Check if kubelet is running - start it if not
if ! systemctl is-active kubelet; then
  echo "Kubelet not running, attempting to start it..."
  systemctl start kubelet
  sleep 5
  systemctl status kubelet > /var/log/eks-debug/kubelet-status.log
fi

# Create a file with debugging commands for easier troubleshooting via SSM
cat > /home/ec2-user/debug-eks.sh << 'EOF'
#!/bin/bash
echo "EKS Node Debug Helper"
echo "===================="
echo "1. View bootstrap logs:              cat /var/log/eks-bootstrap.log"
echo "2. View kubelet logs:                journalctl -u kubelet"
echo "3. Check kubelet status:             systemctl status kubelet"
echo "4. View kubelet config:              ls -la /var/lib/kubelet"
echo "5. View system logs:                 tail -100 /var/log/messages"
echo "6. Test API connectivity:            curl -k \$(cat /var/log/eks-debug/cluster-endpoint.txt)/healthz"
echo "7. View instance identity:           cat /var/log/eks-debug/instance-identity.json"
echo "8. View all debug logs:              ls -la /var/log/eks-debug/"
echo "9. Check CNI networks:               ls -la /etc/cni/net.d/ && cat /etc/cni/net.d/*"
echo "10. Check certificates:              ls -la /etc/kubernetes/pki/"
echo ""
echo "11. Check AWS VPC CNI addon status:  aws eks describe-addon --cluster-name \$(cat /var/log/eks-debug/cluster-name.txt) --addon-name vpc-cni --region \$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)"
echo "12. Check node logs in AWS CNI:      kubectl logs -n kube-system -l k8s-app=aws-node --tail=50"
echo "13. Restart kubelet:                 sudo systemctl restart kubelet"
echo ""
EOF
chmod +x /home/ec2-user/debug-eks.sh

# Ensure permissions are set for SSM access
chmod -R 755 /var/log/eks-debug
chmod 644 /var/log/eks-bootstrap.log

echo "=========== Bootstrap process completed ==========="
echo "Debug logs available at /var/log/eks-bootstrap.log and /var/log/eks-debug/"
echo "Run /home/ec2-user/debug-eks.sh for troubleshooting help"

# Keep kubelet running even if bootstrap failed
if [ $$BOOTSTRAP_EXIT_CODE -ne 0 ]; then
  echo "Bootstrap failed, but keeping kubelet running for debugging"
  systemctl restart kubelet
fi

# End of script
--==BOUNDARY==--
USERDATA
}

resource "aws_launch_template" "this" {
  name_prefix            = "${var.cluster_name}-${var.node_group_name}-"
  description            = "Launch template for ${var.cluster_name} ${var.node_group_name} node group"
  update_default_version = true

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.disk_size
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  }

  monitoring {
    enabled = true
  }

  # Enable IMDSv2
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  # User data for bootstrap script with proper MIME format
  user_data = base64encode(local.user_data)

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      {
        Name = "${var.cluster_name}-${var.node_group_name}-node"
      },
      var.tags
    )
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Security group for the node group
resource "aws_security_group" "node_group" {
  name        = "${var.cluster_name}-${var.node_group_name}-node-sg-${random_id.node_group.hex}"
  description = "Security group for ${var.cluster_name} ${var.node_group_name} node group"
  vpc_id      = var.vpc_id

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow nodes to communicate with each other
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  # Allow worker Kubelets and pods to receive communication from the cluster control plane
  ingress {
    from_port       = 1025
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [var.cluster_security_group_id]
  }

  # Allow worker nodes to receive HTTPS from the cluster control plane
  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [var.cluster_security_group_id]
  }

  # Allow worker nodes to receive kubelet communication from the cluster control plane
  ingress {
    from_port       = 10250
    to_port         = 10250
    protocol        = "tcp"
    security_groups = [var.cluster_security_group_id]
  }

  # Allow UDP traffic for DNS resolution and cluster communication
  ingress {
    from_port       = 53
    to_port         = 53
    protocol        = "udp" 
    security_groups = [var.cluster_security_group_id]
  }
  
  # Allow UDP traffic for general cluster communication
  ingress {
    from_port       = 1025
    to_port         = 65535
    protocol        = "udp"
    security_groups = [var.cluster_security_group_id]
  }

  tags = merge(
    {
      Name = "${var.cluster_name}-${var.node_group_name}-node-sg"
    },
    var.tags
  )
}

# IAM role for the EKS node group
resource "aws_iam_role" "node_group" {
  name = "ng-${var.node_group_name}-${random_id.node_group.hex}"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })

  tags = var.tags
}

# Attach required Amazon EKS worker node policies to the node group role
resource "aws_iam_role_policy_attachment" "node_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node_group.name
}

resource "aws_iam_role_policy_attachment" "node_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node_group.name
}

resource "aws_iam_role_policy_attachment" "node_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node_group.name
}

# Allow SSM access for troubleshooting
resource "aws_iam_role_policy_attachment" "node_AmazonSSMManagedInstanceCore" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.node_group.name
}

resource "aws_eks_node_group" "this" {
  cluster_name    = var.cluster_name
  node_group_name = local.final_node_group_name
  node_role_arn   = aws_iam_role.node_group.arn
  subnet_ids      = var.subnet_ids

  launch_template {
    id      = aws_launch_template.this.id
    version = aws_launch_template.this.latest_version
  }

  scaling_config {
    desired_size = var.desired_capacity
    min_size     = var.min_capacity
    max_size     = var.max_capacity
  }

  # We're using launch template instead
  instance_types = null
  disk_size      = null

  # Configure update parameters for the node group
  update_config {
    max_unavailable = var.max_unavailable_percentage != null ? null : var.max_unavailable
    max_unavailable_percentage = var.max_unavailable_percentage
  }

  labels = var.node_labels

  # Configure taints for the node group
  dynamic "taint" {
    for_each = var.node_taints
    content {
      key    = taint.value.key
      value  = lookup(taint.value, "value", null)
      effect = taint.value.effect
    }
  }

  # Ensure the IAM Role is created before the node group
  depends_on = [
    aws_iam_role_policy_attachment.node_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.node_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.node_AmazonEC2ContainerRegistryReadOnly,
    aws_iam_role_policy_attachment.node_AmazonSSMManagedInstanceCore,
  ]

  tags = var.tags

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
    create_before_destroy = true
    # Add a longer timeout for node group operations
    prevent_destroy = false
  }

  # Add timeouts for node group operations
  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}

# Allow the cluster security group to accept connections from the node group
# Use count to allow skipping this if it already exists (to avoid duplicates)
resource "aws_security_group_rule" "cluster_to_node" {
  # Only create if explicitly enabled, defaults to false to avoid duplicates
  count                    = var.create_cluster_sg_rule ? 1 : 0
  description              = "Allow cluster security group to receive communication from node security group"
  security_group_id        = var.cluster_security_group_id
  source_security_group_id = aws_security_group.node_group.id
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  type                     = "ingress"
} 
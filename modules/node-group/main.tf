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
  
  # Smaller, simplified user data to stay under AWS limit of 16384 bytes
  user_data = <<-USERDATA
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="==BOUNDARY=="

--==BOUNDARY==
Content-Type: text/x-shellscript; charset="us-ascii"

#!/bin/bash
# Simplified EKS Node bootstrap script with critical CNI handling
set -x
exec > /var/log/eks-bootstrap.log 2>&1

echo "Starting bootstrap process for node group: ${var.node_group_name}, cluster: ${var.cluster_name}"

# Set cluster identification
echo "${var.cluster_name}" > /etc/eks-cluster-name
echo "${local.final_node_group_name}" > /etc/eks-nodegroup-name

# Create essential directories
mkdir -p /etc/cni/net.d /opt/cni/bin /var/log/aws-routed-eni /var/run/aws-node

# Create a temporary CNI config if needed
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

# Create placeholder CNI binaries if needed
if [ ! -f "/opt/cni/bin/aws-cni" ]; then
  echo '#!/bin/sh
echo "Placeholder aws-cni binary"
exit 0' > /opt/cni/bin/aws-cni
  chmod +x /opt/cni/bin/aws-cni
  
  echo '#!/bin/sh
echo "Placeholder egress-cni binary"
exit 0' > /opt/cni/bin/egress-cni
  chmod +x /opt/cni/bin/egress-cni
fi

# Prepare kubelet with override to use CNI
mkdir -p /etc/systemd/system/kubelet.service.d/
echo '[Service]
Environment="KUBELET_EXTRA_ARGS=--node-labels=eks.amazonaws.com/nodegroup=${local.final_node_group_name},eks.amazonaws.com/nodegroup-image=ami-custom-eks,node.kubernetes.io/node-group=${var.node_group_name},${local.node_labels_string} --max-pods=110 --register-with-taints= --network-plugin=kubenet --cni-conf-dir=/etc/cni/net.d --cni-bin-dir=/opt/cni/bin"' > /etc/systemd/system/kubelet.service.d/10-cni-bootstrap.conf
systemctl daemon-reload

# Bootstrap with explicit EKS cluster and nodegroup flags
/etc/eks/bootstrap.sh ${var.cluster_name} \
  --b64-cluster-ca ${var.cluster_certificate_authority_data} \
  --apiserver-endpoint ${var.cluster_endpoint} \
  --dns-cluster-ip 10.100.0.10 \
  --kubelet-extra-args "--node-labels=eks.amazonaws.com/nodegroup=${local.final_node_group_name},eks.amazonaws.com/capacityType=${var.capacity_type},eks.amazonaws.com/nodegroup-image=ami-custom-eks,node.kubernetes.io/node-group=${var.node_group_name},${local.node_labels_string} --max-pods=110"

BOOTSTRAP_EXIT=$?
echo "Bootstrap exit code: $BOOTSTRAP_EXIT"

# Create a helper script for debugging
cat > /home/ec2-user/debug-eks.sh << 'EOF'
#!/bin/bash
echo "EKS Node Debug Helper"
echo "===================="
echo "1. View bootstrap logs:    cat /var/log/eks-bootstrap.log"
echo "2. View kubelet logs:      journalctl -u kubelet"
echo "3. Check kubelet status:   systemctl status kubelet"
echo "4. Check CNI networks:     ls -la /etc/cni/net.d/ && cat /etc/cni/net.d/*"
echo "5. Restart kubelet:        sudo systemctl restart kubelet"
echo "6. Check node registration: kubectl get nodes --show-labels"
EOF
chmod +x /home/ec2-user/debug-eks.sh

# Create a simplified fix-node-registration script without parameter expansion
cat > /home/ec2-user/fix-node-registration.sh << 'EOF'
#!/bin/bash
# Simple script to fix node registration with EKS managed node groups

# Get node information
NODE_NAME=$(hostname)
NODE_GROUP=$(cat /etc/eks-nodegroup-name)
CLUSTER_NAME=$(cat /etc/eks-cluster-name)

echo "Fixing node registration for $NODE_NAME in node group $NODE_GROUP"

# Create a new kubelet config file with the proper labels
cat > /tmp/kubelet-extra-args.conf << INNEREOF
[Service]
Environment="KUBELET_EXTRA_ARGS=--node-labels=eks.amazonaws.com/nodegroup=$NODE_GROUP,eks.amazonaws.com/capacityType=ON_DEMAND,node.kubernetes.io/node-group=$NODE_GROUP --max-pods=110"
INNEREOF

# Install the new config
sudo mv /tmp/kubelet-extra-args.conf /etc/systemd/system/kubelet.service.d/kubelet-extra-args.conf
sudo chmod 644 /etc/systemd/system/kubelet.service.d/kubelet-extra-args.conf

# Restart kubelet
sudo systemctl daemon-reload
sudo systemctl restart kubelet

echo "Node registration fix applied. Check status with kubectl get nodes"
EOF
chmod +x /home/ec2-user/fix-node-registration.sh

# Clean up and restart kubelet
rm -f /etc/systemd/system/kubelet.service.d/10-cni-bootstrap.conf
systemctl daemon-reload
systemctl restart kubelet

echo "Bootstrap process completed"
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

  # Ensure all required EKS tags are included
  tag_specifications {
    resource_type = "instance"
    tags = merge(
      {
        Name = "${var.cluster_name}-${var.node_group_name}-node"
        "kubernetes.io/cluster/${var.cluster_name}" = "owned"
        "eks:cluster-name" = var.cluster_name
        "eks:nodegroup-name" = local.final_node_group_name
      },
      var.tags
    )
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(
      {
        Name = "${var.cluster_name}-${var.node_group_name}-volume"
        "kubernetes.io/cluster/${var.cluster_name}" = "owned"
      },
      var.tags
    )
  }

  # Ensure the network interface is also tagged
  tag_specifications {
    resource_type = "network-interface"
    tags = merge(
      {
        Name = "${var.cluster_name}-${var.node_group_name}-eni"
        "kubernetes.io/cluster/${var.cluster_name}" = "owned"
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
  capacity_type   = var.capacity_type

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

  # Add resource tags to help with identification
  tags = merge(
    {
      "Name" = "${var.cluster_name}-${var.node_group_name}"
      "kubernetes.io/cluster/${var.cluster_name}" = "owned"
      "k8s.io/cluster-autoscaler/enabled" = "true"
      "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
    },
    var.tags
  )

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
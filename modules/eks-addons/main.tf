# VPC CNI needs to be deployed first to provide networking for other addons
resource "aws_eks_addon" "vpc_cni" {
  count = var.enable_vpc_cni ? 1 : 0

  cluster_name = var.cluster_name
  addon_name   = "vpc-cni"
  
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  
  # Simplified configuration with minimal settings to ensure compatibility
  configuration_values = jsonencode({
    env = {
      # Increase IPs per node for high density workloads
      WARM_ENI_TARGET = "1"
      WARM_IP_TARGET = "5"
      # Use prefix delegation for higher pod density if needed
      ENABLE_PREFIX_DELEGATION = "false"
      # Set higher log level for debugging
      AWS_VPC_K8S_CNI_LOGLEVEL = "DEBUG"
      # Ensure custom network config is enabled
      AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG = "true"
    },
    resources = {
      limits = {
        cpu = "100m"
        memory = "128Mi"
      },
      requests = {
        cpu = "100m" 
        memory = "128Mi"
      }
    },
    tolerations = [
      {
        key = "dedicated"
        value = "monitoring"
        effect = "NoSchedule"
      },
      {
        key = "dedicated"
        value = "management"
        effect = "NoSchedule"
      }
    ]
  })
  
  # Wait for node groups to be ready
  timeouts {
    create = "15m"
    update = "15m"
    delete = "15m"
  }
}

# kube-proxy depends on VPC CNI
resource "aws_eks_addon" "kube_proxy" {
  count = var.enable_kube_proxy ? 1 : 0

  cluster_name = var.cluster_name
  addon_name   = "kube-proxy"
  
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  
  # Explicitly depend on VPC CNI
  depends_on = [aws_eks_addon.vpc_cni]
  
  # Wait for node groups to be ready
  timeouts {
    create = "15m"
    update = "15m"
    delete = "15m"
  }
}

# CoreDNS depends on VPC CNI and kube-proxy
resource "aws_eks_addon" "coredns" {
  count = var.enable_coredns ? 1 : 0

  cluster_name = var.cluster_name
  addon_name   = "coredns"
  
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  
  # The CoreDNS addon uses a different configuration schema
  configuration_values = jsonencode({
    affinity = {
      nodeAffinity = null
    }
    tolerations = [
      {
        key = "dedicated"
        value = "monitoring"
        effect = "NoSchedule"
        operator = "Equal"
      },
      {
        key = "dedicated" 
        value = "management"
        effect = "NoSchedule"
        operator = "Equal"
      }
    ]
  })
  
  # Explicitly depend on VPC CNI and kube-proxy to ensure proper order
  depends_on = [aws_eks_addon.vpc_cni, aws_eks_addon.kube_proxy]
  
  # Wait for node groups to be ready
  timeouts {
    create = "20m"
    update = "20m"
    delete = "20m"
  }
}

# Configure the kubernetes provider
provider "kubernetes" {
  host                   = var.cluster_endpoint
  cluster_ca_certificate = base64decode(var.cluster_certificate_authority_data)
  
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
  }
} 
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  # Enable node groups
  eks_managed_node_group_defaults = {
    ami_type               = "AL2_x86_64"
    disk_size              = 50
    instance_types         = ["t3.medium"]
    vpc_security_group_ids = []
  }

  # Setting to empty map as we'll create node groups separately
  eks_managed_node_groups = {}

  # Enable private access to the cluster's API endpoint
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = var.cluster_endpoint_public_access

  # Allow restricted access to the Kubernetes API server
  cluster_security_group_additional_rules = {
    api_ingress_from_allowed_cidr_blocks = {
      description = "Allow inbound traffic to Kubernetes API from allowed CIDR blocks"
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      type        = "ingress"
      cidr_blocks = var.api_access_cidr_blocks
    }
    # Allow node groups to communicate with control plane
    egress_nodes_ephemeral_ports_tcp = {
      description                = "Allow nodes to communicate with each other and control plane"
      protocol                   = "tcp"
      from_port                  = 1025
      to_port                    = 65535
      type                       = "egress"
      source_node_security_group = true
    }
  }

  node_security_group_additional_rules = {
    # Allow nodes to communicate with each other
    ingress_self_all = {
      description = "Allow nodes to communicate with each other"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    # Allow worker nodes to communicate with EKS control plane
    ingress_cluster_all = {
      description                   = "Allow worker nodes to communicate with control plane"
      protocol                      = "-1"
      from_port                     = 0
      to_port                       = 0
      type                          = "ingress"
      source_cluster_security_group = true
    }
    # Allow worker nodes to access the internet
    egress_all = {
      description = "Allow worker nodes to access the internet"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "egress"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  # Disable EKS Addons initially - we'll enable them after node groups are created
  # Use var.enable_cluster_addons to control whether addons are created
  cluster_addons = var.enable_cluster_addons ? {
    coredns = {
      most_recent = true
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
    }
    kube-proxy = {
      most_recent = true
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
    }
    vpc-cni = {
      most_recent = true
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
      # Configuration options
      configuration_values = jsonencode({
        env = {
          # Increase IPs per node for high density workloads
          WARM_ENI_TARGET = "2"
          WARM_IP_TARGET = "10"
          # Enable prefix assignment mode for higher maximum pod density
          ENABLE_PREFIX_DELEGATION = "true"
        }
      })
    }
  } : {}

  # IAM roles for service accounts
  enable_irsa = true

  tags = var.tags
}

# Use the outputs from the module directly rather than through data sources
data "aws_eks_cluster_auth" "this" {
  name = var.cluster_name
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
  
  # Don't verify TLS certificate until the cluster is fully configured
  ignore_annotations     = []
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
  }
} 
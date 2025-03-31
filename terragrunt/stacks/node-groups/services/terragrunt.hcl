include {
  path = find_in_parent_folders()
}

dependency "vpc" {
  config_path = "../../vpc"
}

dependency "eks" {
  config_path = "../../eks-cluster"
}

# Add a dependency on the EKS addons to ensure VPC CNI is deployed first
dependency "eks_addons" {
  config_path = "../../eks-addons"
}

# Override the required_providers.tf generation for this module
# since the node-group module already has a versions.tf file
generate "empty_required_providers" {
  path      = "required_providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = "# This file intentionally left empty to prevent conflicts with the module's versions.tf"
}

terraform {
  source = "../../../../modules/node-group"
}

inputs = {
  # Cluster details
  cluster_name                    = dependency.eks.outputs.cluster_name
  cluster_endpoint                = dependency.eks.outputs.cluster_endpoint
  cluster_certificate_authority_data = dependency.eks.outputs.cluster_certificate_authority_data
  cluster_security_group_id       = dependency.eks.outputs.cluster_security_group_id
  
  # Node group configuration
  node_group_name                 = "svc"
  vpc_id                          = dependency.vpc.outputs.vpc_id
  subnet_ids                      = dependency.vpc.outputs.private_subnets
  
  # Instance specifications
  instance_types                  = ["t3.medium"]
  capacity_type                   = "ON_DEMAND"  # or "SPOT" for spot instances
  disk_size                       = 50
  
  # Auto-scaling configuration
  desired_capacity                = 2
  min_capacity                    = 1
  max_capacity                    = 4
  
  # Labels and taints
  node_labels = {
    "role" = "services"
    "tier" = "application"
  }
  
  # No taints for services node group
  node_taints = []
  
  # Explicitly set the create_cluster_sg_rule to false to avoid duplicate rules
  create_cluster_sg_rule          = false
  
  # Update strategy configuration to avoid update issues
  max_unavailable = null # Set this to null when using percentage instead
  max_unavailable_percentage = 50 # Allow 50% of nodes to be unavailable during updates
} 
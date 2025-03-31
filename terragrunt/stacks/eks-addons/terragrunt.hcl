include {
  path = find_in_parent_folders()
}

dependency "vpc" {
  config_path = "../vpc"
}

dependency "eks" {
  config_path = "../eks-cluster"
}

# Additional dependencies on node groups to ensure they exist before enabling addons
dependency "node_group_monitoring" {
  config_path = "../node-groups/monitoring"
  skip_outputs = true
}

dependency "node_group_management" {
  config_path = "../node-groups/management"
  skip_outputs = true
}

# Override the required_providers.tf generation for this module
# since the eks-addons module already has a versions.tf file
generate "empty_required_providers" {
  path      = "required_providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = "# This file intentionally left empty to prevent conflicts with the module's versions.tf"
}

# Using a different source for addons to avoid creating a new cluster
terraform {
  source = "../../../modules/eks-addons"
}

inputs = {
  # EKS Cluster Configuration
  cluster_name    = dependency.eks.outputs.cluster_name
  cluster_endpoint = dependency.eks.outputs.cluster_endpoint
  cluster_certificate_authority_data = dependency.eks.outputs.cluster_certificate_authority_data
  
  # Enable addons now that node groups exist
  enable_coredns = true
  enable_kube_proxy = true
  enable_vpc_cni = true
} 
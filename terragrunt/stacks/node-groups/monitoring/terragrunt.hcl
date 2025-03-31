include {
  path = find_in_parent_folders()
}

dependency "vpc" {
  config_path = "../../vpc"
}

dependency "eks" {
  config_path = "../../eks-cluster"
}

# Do NOT add a dependency on eks-addons for monitoring, 
# as eks-addons has a dependency on monitoring node group
# (This prevents a circular dependency)

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
  vpc_id                          = dependency.vpc.outputs.vpc_id
  
  # Node group configuration
  node_group_name                 = "mon"
  subnet_ids                      = dependency.vpc.outputs.private_subnets
  
  # Capacity (can adjust to your needs)
  desired_capacity                = 2
  min_capacity                    = 2
  max_capacity                    = 4
  instance_types                  = ["t3.medium"]
  disk_size                       = 50
  
  # Labels and taints
  node_labels = {
    "role" = "monitoring"
    "tier" = "management"
  }
  
  # Taint the monitoring nodes to ensure only monitoring workloads run on them
  node_taints = [
    {
      key = "dedicated"
      value = "monitoring"
      effect = "NO_SCHEDULE"
    }
  ]
  
  # Security group and IAM config
  create_cluster_sg_rule = true
} 
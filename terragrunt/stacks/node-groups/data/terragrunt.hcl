include {
  path = find_in_parent_folders()
}

dependency "vpc" {
  config_path = "../../vpc"
}

dependency "eks" {
  config_path = "../../eks-cluster"
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
  # EKS Cluster details
  cluster_name                      = dependency.eks.outputs.cluster_name
  cluster_endpoint                  = dependency.eks.outputs.cluster_endpoint
  cluster_certificate_authority_data = dependency.eks.outputs.cluster_certificate_authority_data
  cluster_security_group_id         = dependency.eks.outputs.cluster_security_group_id
  vpc_id                            = dependency.vpc.outputs.vpc_id
  
  # Region for endpoints and services
  region = "us-east-1"
  
  # Node Group configuration - using a short name to avoid potential length issues
  node_group_name = "dat"
  subnet_ids      = dependency.vpc.outputs.private_subnets
  
  # Node Group capacity
  desired_capacity = 2
  min_capacity     = 2
  max_capacity     = 5
  
  # Instance configuration
  instance_types = ["r5.2xlarge"]
  disk_size      = 100
  
  # Node labels and taints
  node_labels = {
    "node-type" = "data"
    "workload"  = "data"
  }
  
  node_taints = [
    {
      key    = "dedicated"
      value  = "data"
      effect = "NO_SCHEDULE"
    }
  ]
  
  # Avoid duplicate security group rules since EKS automatically creates them
  create_cluster_sg_rule = false
} 
include {
  path = find_in_parent_folders()
}

dependency "vpc" {
  config_path = "../vpc"
}

# Override the required_providers.tf generation for this module
# since the EKS module already has a versions.tf file
generate "empty_required_providers" {
  path      = "required_providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = "# This file intentionally left empty to prevent conflicts with the module's versions.tf"
}

terraform {
  source = "../../../modules/eks"
}

inputs = {
  # EKS Cluster Configuration
  cluster_name    = "eks-cluster"
  cluster_version = "1.28"
  
  # VPC Configuration
  vpc_id     = dependency.vpc.outputs.vpc_id
  subnet_ids = dependency.vpc.outputs.private_subnets
  
  # Endpoint access configuration
  cluster_endpoint_public_access = true
  
  # API access CIDR blocks - restrict as needed
  api_access_cidr_blocks = ["0.0.0.0/0"]
  
  # Disable addons initially - we'll enable them after node groups
  enable_cluster_addons = false
} 
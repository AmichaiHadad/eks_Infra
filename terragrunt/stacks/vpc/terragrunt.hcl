include {
  path = find_in_parent_folders()
}

# Override the required_providers.tf generation for this module
# since the VPC module already has a versions.tf file
generate "empty_required_providers" {
  path      = "required_providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = "# This file intentionally left empty to prevent conflicts with the module's versions.tf"
}

terraform {
  source = "../../../modules/vpc"
}

inputs = {
  # VPC Configuration
  vpc_name = "eks-vpc"
  vpc_cidr = "10.0.0.0/16"
  
  # Availability Zones
  azs = ["us-east-1a", "us-east-1b", "us-east-1c"]
  
  # CIDR blocks for subnets
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  
  # NAT Gateway configuration
  single_nat_gateway     = false
  one_nat_gateway_per_az = true
  enable_vpn_gateway     = false
  
  # Required for EKS and name to be used for tags
  cluster_name = "eks-cluster"
} 
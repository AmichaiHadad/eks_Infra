include {
  path = find_in_parent_folders()
}

dependency "vpc" {
  config_path = "../../vpc"
}

dependency "eks" {
  config_path = "../../eks-cluster"
}

# Add a stronger dependency on the EKS addons to ensure VPC CNI is deployed first
dependency "eks_addons" {
  config_path = "../../eks-addons"
  mock_outputs = {
    vpc_cni_addon_id = "mock-vpc-cni-addon"
  }
  skip_outputs = false
}

# Add a sleep after VPC CNI deployment to ensure it's properly initialized
generate "sleep_after_addons" {
  path = "sleep_after_addons.tf"
  if_exists = "overwrite"
  contents = <<-EOF
    resource "null_resource" "wait_for_cni" {
      triggers = {
        vpc_cni_addon_id = dependency.eks_addons.outputs.vpc_cni_addon_id
      }
      
      provisioner "local-exec" {
        command = "echo 'Waiting for VPC CNI to initialize...' && sleep 120"
      }
    }
  EOF
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

  # Add extra CLI arguments to ensure we wait for the VPC CNI addon
  extra_arguments "retry_lock" {
    commands = ["apply", "plan", "destroy"]
    arguments = [
      "-lock-timeout=20m"
    ]
  }
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
  
  # Instance specifications - use on-demand for reliability
  instance_types                  = ["t3.medium"]
  capacity_type                   = "ON_DEMAND"
  disk_size                       = 50
  
  # Auto-scaling configuration
  desired_capacity                = 2
  min_capacity                    = 1
  max_capacity                    = 4
  
  # Labels and taints
  node_labels = {
    "role" = "services"
    "tier" = "application"
    "cni-initialized" = "true"  # Help identify that these nodes should have CNI initialized
  }
  
  # No taints for services node group
  node_taints = []
  
  # Explicitly set the create_cluster_sg_rule to false to avoid duplicate rules
  create_cluster_sg_rule          = false
  
  # Update strategy configuration to avoid update issues
  max_unavailable = null # Set this to null when using percentage instead
  max_unavailable_percentage = 50 # Allow 50% of nodes to be unavailable during updates
  
  # Ensure terraform knows this depends on the VPC CNI addon
  depends_on = ["null_resource.wait_for_cni"]
} 
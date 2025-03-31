locals {
  # Parse the file path to extract the environment and stack
  path_components = split("/", path_relative_to_include())
  
  # Common tags for all resources
  common_tags = {
    ManagedBy   = "Terragrunt"
    Environment = "Production"
    Project     = "EKS-Cluster"
  }
}

# Remote state configuration
remote_state {
  backend = "s3"
  config = {
    bucket         = "eks-terraform-state-${get_aws_account_id()}"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

# Generate providers.tf file with provider configurations
# But without required_providers block to avoid conflicts with modules that have versions.tf
generate "providers" {
  path      = "providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "us-east-1"
  
  # Configure robust retry behavior for AWS API calls
  max_retries = 25
  retry_mode = "standard"

  # Add explicit configuration for API operations
  skip_metadata_api_check = true
  skip_requesting_account_id = false
  
  # Default tags to apply to all resources
  default_tags {
    tags = {
      ManagedBy = "Terragrunt"
      Project = "EKS-Cluster"
    }
  }
}

provider "random" {
}
EOF
}

# Generate a separate file for required providers only when needed
generate "required_providers" {
  path      = "required_providers.tf"
  if_exists = "skip" # Skip if a versions.tf exists in the module
  contents  = <<EOF
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.47.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.1.0"
    }
  }
}
EOF
}

# Configure terraform version requirements
terraform {
  extra_arguments "common_vars" {
    commands = [
      "plan",
      "apply",
      "destroy",
      "import",
      "push",
      "refresh",
    ]

    # Increase parallelism and configure lock timeouts
    arguments = [
      "-parallelism=30",
      "-lock-timeout=20m"
    ]
  }
}

# Avoid lock timeout issues
retryable_errors = [
  "(?s).*Failed to acquire the state lock.*",
  "(?s).*Error acquiring the state lock.*",
  "(?s).*Error: conflict operation in progress.*",
  "(?s).*OneOrMoreErrors: error getting.*",
  "(?s).*RequestError: send request failed.*",
  "(?s).*Error: InvalidParameterException.*",
  "(?s).*Error: RequestError: multiple error.*",
  "(?s).*Error: timeout while waiting for state to become.*"
]

# Configure retry sleep for Terragrunt operations
retry_sleep_interval_sec = 5
retry_max_attempts = 10

# Inputs that are common to all stacks
inputs = {
  region = "us-east-1"
  tags   = local.common_tags
} 
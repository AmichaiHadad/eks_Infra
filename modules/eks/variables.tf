variable "region" {
  description = "AWS region"
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version to use for the EKS cluster"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC where the EKS cluster will be created"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs where the EKS cluster will be created"
  type        = list(string)
}

variable "cluster_endpoint_public_access" {
  description = "Indicates whether or not the EKS cluster's API endpoint is publicly accessible"
  type        = bool
  default     = false
}

variable "api_access_cidr_blocks" {
  description = "List of CIDR blocks that can access the Kubernetes API server"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_cluster_addons" {
  description = "Whether to enable cluster addons like CoreDNS, kube-proxy, etc. Disable initially and enable after node groups."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Map of tags to apply to all resources"
  type        = map(string)
  default     = {}
} 
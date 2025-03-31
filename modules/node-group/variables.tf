variable "region" {
  description = "AWS region"
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_endpoint" {
  description = "Endpoint of the EKS cluster API server"
  type        = string
  default     = ""
}

variable "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data for the EKS cluster"
  type        = string
  default     = ""
}

variable "node_group_name" {
  description = "Name of the node group"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs to deploy the node group in"
  type        = list(string)
}

variable "vpc_id" {
  description = "VPC ID for the node group security group"
  type        = string
}

variable "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  type        = string
}

variable "desired_capacity" {
  description = "Desired number of nodes in the node group"
  type        = number
}

variable "min_capacity" {
  description = "Minimum number of nodes in the node group"
  type        = number
}

variable "max_capacity" {
  description = "Maximum number of nodes in the node group"
  type        = number
}

variable "instance_types" {
  description = "List of instance types for the node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "capacity_type" {
  description = "Type of capacity associated with the EKS Node Group. Valid values: ON_DEMAND, SPOT"
  type        = string
  default     = "ON_DEMAND"
}

variable "disk_size" {
  description = "Disk size in GiB for worker nodes"
  type        = number
  default     = 20
}

variable "max_unavailable" {
  description = "Maximum number of nodes unavailable during node group updates"
  type        = number
  default     = 1
}

variable "max_unavailable_percentage" {
  description = "Maximum percentage of nodes unavailable during node group updates"
  type        = number
  default     = null
}

variable "force_update_version" {
  description = "Force update for launch template version changes"
  type        = bool
  default     = false
}

variable "node_labels" {
  description = "Kubernetes labels to apply to all nodes in the node group"
  type        = map(string)
  default     = {}
}

variable "node_taints" {
  description = "Kubernetes taints to apply to all nodes in the node group"
  type        = list(object({
    key    = string
    value  = optional(string)
    effect = string
  }))
  default     = []
}

variable "tags" {
  description = "Map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "create_cluster_sg_rule" {
  description = "Whether to create a security group rule that allows the cluster to communicate with the nodes (disable to avoid duplicate rules)"
  type        = bool
  default     = false
} 
variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_endpoint" {
  description = "Endpoint for the EKS cluster API server"
  type        = string
}

variable "cluster_certificate_authority_data" {
  description = "Certificate authority data for the EKS cluster"
  type        = string
}

variable "enable_coredns" {
  description = "Enable CoreDNS addon"
  type        = bool
  default     = true
}

variable "enable_kube_proxy" {
  description = "Enable kube-proxy addon"
  type        = bool
  default     = true
}

variable "enable_vpc_cni" {
  description = "Enable VPC CNI addon"
  type        = bool
  default     = true
} 
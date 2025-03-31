variable "region" {
  description = "AWS region"
  type        = string
}

variable "vpc_name" {
  description = "Name of VPC"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
}

variable "azs" {
  description = "Availability zones for VPC"
  type        = list(string)
}

variable "private_subnets" {
  description = "Private subnets CIDR blocks"
  type        = list(string)
}

variable "public_subnets" {
  description = "Public subnets CIDR blocks"
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "Use a single NAT gateway for all private subnets"
  type        = bool
  default     = false
}

variable "one_nat_gateway_per_az" {
  description = "Use one NAT gateway per AZ"
  type        = bool
  default     = true
}

variable "enable_vpn_gateway" {
  description = "Enable VPN gateway"
  type        = bool
  default     = false
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "tags" {
  description = "Map of tags to apply to all resources"
  type        = map(string)
  default     = {}
} 
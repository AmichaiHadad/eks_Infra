output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

output "private_subnets" {
  description = "List of IDs of private subnets"
  value       = module.vpc.private_subnets
}

output "public_subnets" {
  description = "List of IDs of public subnets"
  value       = module.vpc.public_subnets
}

output "private_subnet_cidrs" {
  description = "List of CIDR blocks of private subnets"
  value       = module.vpc.private_subnets_cidr_blocks
}

output "public_subnet_cidrs" {
  description = "List of CIDR blocks of public subnets"
  value       = module.vpc.public_subnets_cidr_blocks
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "nat_public_ips" {
  description = "List of public Elastic IPs created for AWS NAT Gateway"
  value       = module.vpc.nat_public_ips
}

output "vpc_endpoint_s3_id" {
  description = "The ID of S3 VPC endpoint"
  value       = aws_vpc_endpoint.s3.id
}

output "vpc_endpoint_ecr_api_id" {
  description = "The ID of ECR API VPC endpoint"
  value       = aws_vpc_endpoint.ecr_api.id
}

output "vpc_endpoint_ecr_dkr_id" {
  description = "The ID of ECR Docker VPC endpoint"
  value       = aws_vpc_endpoint.ecr_dkr.id
}

output "vpc_endpoint_ec2_id" {
  description = "The ID of EC2 VPC endpoint"
  value       = aws_vpc_endpoint.ec2.id
}

output "vpc_endpoint_logs_id" {
  description = "The ID of CloudWatch Logs VPC endpoint"
  value       = aws_vpc_endpoint.logs.id
}

output "vpc_endpoint_eks_id" {
  description = "The ID of EKS VPC endpoint"
  value       = aws_vpc_endpoint.eks.id
}

output "vpc_endpoint_sts_id" {
  description = "The ID of STS VPC endpoint"
  value       = aws_vpc_endpoint.sts.id
}

output "vpc_endpoint_ssm_id" {
  description = "The ID of SSM VPC endpoint"
  value       = aws_vpc_endpoint.ssm.id
}

output "vpc_endpoint_ssmmessages_id" {
  description = "The ID of SSM Messages VPC endpoint"
  value       = aws_vpc_endpoint.ssmmessages.id
}

output "vpc_endpoints_security_group_id" {
  description = "The ID of the security group used for VPC endpoints"
  value       = aws_security_group.vpc_endpoints.id
} 
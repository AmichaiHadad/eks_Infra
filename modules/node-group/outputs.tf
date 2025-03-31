output "node_group_id" {
  description = "The ID of the node group"
  value       = aws_eks_node_group.this.id
}

output "node_group_arn" {
  description = "Amazon Resource Name (ARN) of the node group"
  value       = aws_eks_node_group.this.arn
}

output "node_group_status" {
  description = "Status of the node group"
  value       = aws_eks_node_group.this.status
}

output "node_group_role_arn" {
  description = "Amazon Resource Name (ARN) of the IAM role for the node group"
  value       = aws_iam_role.node_group.arn
}

output "node_group_role_name" {
  description = "Name of the IAM role for the node group"
  value       = aws_iam_role.node_group.name
} 
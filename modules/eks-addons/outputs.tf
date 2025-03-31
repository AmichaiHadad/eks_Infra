output "coredns_addon_id" {
  description = "ID of the CoreDNS addon"
  value       = var.enable_coredns ? aws_eks_addon.coredns[0].id : null
}

output "kube_proxy_addon_id" {
  description = "ID of the kube-proxy addon"
  value       = var.enable_kube_proxy ? aws_eks_addon.kube_proxy[0].id : null
}

output "vpc_cni_addon_id" {
  description = "ID of the VPC CNI addon"
  value       = var.enable_vpc_cni ? aws_eks_addon.vpc_cni[0].id : null
} 
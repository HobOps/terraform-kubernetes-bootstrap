output "cluster_name" {
  description = "Cluster name passed into the module."
  value       = var.cluster_name
}

output "gateway_name" {
  description = "Shared Gateway name."
  value       = var.gateway_name
}

output "gateway_namespace" {
  description = "Namespace of the shared Gateway."
  value       = var.gateway_namespace
}

output "argocd_hostname" {
  description = "Argo CD UI hostname."
  value       = var.argocd_hostname
}

output "chart_versions" {
  description = "Resolved Helm chart versions."
  value       = local.chart_versions
}

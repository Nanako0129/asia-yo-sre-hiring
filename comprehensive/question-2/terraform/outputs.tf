output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "configure_kubectl" {
  description = "Command that writes the kubeconfig entry for this cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

# kubernetes/application.yaml needs this in its StorageClass parameters.
output "efs_file_system_id" {
  description = "EFS file system id backing the application ReadWriteMany volume."
  value       = module.efs.id
}

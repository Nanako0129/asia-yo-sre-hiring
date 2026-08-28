variable "region" {
  description = "AWS region for the cluster."
  type        = string
  default     = "ap-northeast-1"
}

variable "cluster_name" {
  description = "Name shared by the VPC, the EKS cluster and the EFS file system."
  type        = string
  default     = "asiayo"
}

variable "kubernetes_version" {
  description = "EKS control plane version."
  type        = string
  default     = "1.36"
}

variable "vpc_cidr" {
  description = "CIDR of the VPC. Subnets are carved out of this /16."
  type        = string
  default     = "10.0.0.0/16"
}

variable "node_instance_types" {
  description = "Instance types for the managed node group."
  type        = list(string)
  default     = ["m6i.large"]
}

# No default on purpose: the public API endpoint must never fall back to the world.
variable "admin_cidr" {
  description = "The only source allowed to reach the public EKS API endpoint, e.g. 203.0.113.4/32."
  type        = string

  validation {
    condition     = var.admin_cidr != "0.0.0.0/0"
    error_message = "admin_cidr must not be 0.0.0.0/0; use the operator's own address."
  }
}

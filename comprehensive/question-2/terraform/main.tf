data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # Three AZs is the whole point of the HA requirement; take the first three the region offers.
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.1"

  name = var.cluster_name
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = [for i in range(3) : cidrsubnet(var.vpc_cidr, 8, i)]
  public_subnets  = [for i in range(3) : cidrsubnet(var.vpc_cidr, 8, i + 100)]

  # One NAT per AZ. A single NAT would make one AZ's failure take down egress for all three.
  enable_nat_gateway     = true
  single_nat_gateway     = false
  one_nat_gateway_per_az = true

  enable_dns_hostnames = true

  # The Load Balancer Controller discovers subnets by these tags. Without them
  # it refuses to provision an ALB and the Ingress just sits there.
  public_subnet_tags  = { "kubernetes.io/role/elb" = "1" }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = "1" }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.24.2"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Private access is what the nodes actually use. The public endpoint stays
  # open only to admin_cidr so restricting it does not lock the nodes out.
  endpoint_private_access      = true
  endpoint_public_access       = true
  endpoint_public_access_cidrs = [var.admin_cidr]

  enable_cluster_creator_admin_permissions = true

  addons = {
    coredns                = {}
    kube-proxy             = {}
    vpc-cni                = {}
    eks-pod-identity-agent = {}
    aws-ebs-csi-driver     = {}
    aws-efs-csi-driver     = {}
  }

  eks_managed_node_groups = {
    default = {
      instance_types = var.node_instance_types
      subnet_ids     = module.vpc.private_subnets

      min_size     = 3
      max_size     = 6
      desired_size = 3
    }
  }
}

# --- Pod Identity ------------------------------------------------------------
# Each controller gets its own role. Attaching these policies to the node role
# instead would hand every pod on the node the same AWS permissions.

module "vpc_cni_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.8.2"

  name                      = "${var.cluster_name}-vpc-cni"
  attach_aws_vpc_cni_policy = true
  aws_vpc_cni_enable_ipv4   = true

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "aws-node"
    }
  }
}

module "ebs_csi_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.8.2"

  name                      = "${var.cluster_name}-ebs-csi"
  attach_aws_ebs_csi_policy = true

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "ebs-csi-controller-sa"
    }
  }
}

module "efs_csi_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.8.2"

  name                      = "${var.cluster_name}-efs-csi"
  attach_aws_efs_csi_policy = true

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "efs-csi-controller-sa"
    }
  }
}

module "lb_controller_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.8.2"

  name                            = "${var.cluster_name}-lb-controller"
  attach_aws_lb_controller_policy = true

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
  }
}

# --- Storage -----------------------------------------------------------------
# EFS for the application: an EBS volume can only be re-attached inside its own
# AZ, so three web pods spread across three AZs cannot share one. MySQL is the
# opposite case and gets one EBS volume per instance (see kubernetes/mysql.yaml).

module "efs" {
  source  = "terraform-aws-modules/efs/aws"
  version = "2.2.0"

  name      = "${var.cluster_name}-app"
  encrypted = true

  # One mount target per AZ, otherwise pods in the uncovered AZ cannot mount.
  mount_targets = {
    for i, az in local.azs : az => { subnet_id = module.vpc.private_subnets[i] }
  }

  security_group_vpc_id = module.vpc.vpc_id
  security_group_ingress_rules = {
    nodes = {
      description                  = "NFS from cluster nodes"
      referenced_security_group_id = module.eks.node_security_group_id
    }
  }
}

# --- Controllers -------------------------------------------------------------

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "3.5.0"
  namespace  = "kube-system"

  set = [
    { name = "clusterName", value = module.eks.cluster_name },
    { name = "region", value = var.region },
    { name = "vpcId", value = module.vpc.vpc_id },
    { name = "serviceAccount.name", value = "aws-load-balancer-controller" },
  ]

  depends_on = [module.lb_controller_pod_identity]
}

# A plain StatefulSet gives you three MySQL processes, not a cluster: no
# replication, no writer election, no failover. The operator owns all three.
resource "helm_release" "mysql_operator" {
  name             = "mysql-operator"
  repository       = "https://mysql.github.io/mysql-operator/"
  chart            = "mysql-operator"
  version          = "2.3.0"
  namespace        = "mysql-operator"
  create_namespace = true

  depends_on = [module.eks]
}

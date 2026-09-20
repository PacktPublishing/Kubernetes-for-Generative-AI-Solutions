module "eks" {
  source = "terraform-aws-modules/eks/aws"
  version = "~> 20.37"
  cluster_name = local.name
  cluster_version = "1.36"
  enable_cluster_creator_admin_permissions = true
  cluster_endpoint_public_access = true
  vpc_id = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    eks-mng = {
      instance_types = ["m5.large","m6i.large","m6a.large","m7i.large","m7a.large"]
      max_size = 3
      desired_size = 2
      capacity_type = "SPOT"
    }
  }
  node_security_group_tags = {
    "karpenter.sh/discovery" = local.name
  }
}

output "configure_kubectl" {
  description = "Configure kubectl"
  value = "aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}"
}

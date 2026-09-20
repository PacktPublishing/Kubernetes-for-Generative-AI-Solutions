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
      vpc_security_group_ids = [module.eks.cluster_primary_security_group_id]
      ami_type = "BOTTLEROCKET_x86_64"
      max_size = 3
      desired_size = 3
      capacity_type = "SPOT"
    }
    # eks-gpu-mng = {
    #   instance_types = ["g6.2xlarge"]
    #   vpc_security_group_ids = [module.eks.cluster_primary_security_group_id]
    #   ami_type = "BOTTLEROCKET_x86_64_NVIDIA"
    #   max_size = 2
    #   desired_size = 1
    #   capacity_type = "SPOT"
    #   block_device_mappings = {
    #     # Root volume
    #     xvda = {
    #       device_name = "/dev/xvda"
    #       ebs = {
    #         volume_size           = 100
    #         volume_type           = "gp3"
    #         encrypted             = true
    #         delete_on_termination = true
    #       }
    #     }
    #   }
    #   labels = {
    #     "hub.jupyter.org/node-purpose" = "user"
    #     "nvidia.com/gpu.present" = "true"
    #   }
    #   taints = {
    #     # Ensure only GPU workloads are scheduled on this node group
    #     gpu = {
    #       key    = "nvidia.com/gpu"
    #       value  = "true"
    #       effect = "NO_SCHEDULE"
    #     }
    #   }
    # }
  }
  node_security_group_tags = {
    "karpenter.sh/discovery" = local.name
  }
}
output "configure_kubectl" {
  description = "Configure kubectl"
  value = "aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}"
}
#---------------------------------------------------------------
# IRSA for Llama Fine tuning job
#---------------------------------------------------------------
module "llama_fine_tuning_irsa" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.60"
  role_name = "${module.eks.cluster_name}-llama-fine-tuning"
  role_policy_arns = {
    policy = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  }
  oidc_providers = {
    main = {
      provider_arn = module.eks.oidc_provider_arn
      namespace_service_accounts = ["default:llama-fine-tuning-sa"]
    }
  }
}
resource "kubernetes_service_account_v1" "llama_fine_tuning_sa" {
  metadata {
    name        = "llama-fine-tuning-sa"
    namespace   = "default"
    annotations = { "eks.amazonaws.com/role-arn" : module.llama_fine_tuning_irsa.iam_role_arn }
  }
}
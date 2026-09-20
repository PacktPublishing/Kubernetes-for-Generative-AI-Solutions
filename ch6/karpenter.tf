# REFERENCE ONLY. Do not copy this file into your working directory.
#
# These are the same Karpenter blocks that addons.tf already declares, pulled out
# on their own because Chapter 6 walks through them. addons.tf is what you apply.
# Having both files present gives you "Duplicate module call" and "Duplicate
# resource" errors, and the duplicate persists into Chapters 7, 9 and 12, whose
# addons.tf also declares Karpenter.

# provider "aws" {
#   alias  = "ecr"
#   region = "us-east-1"
# }

# data "aws_ecrpublic_authorization_token" "token" {
#   provider = aws.ecr
# }

################################################################################
# Controller & Node IAM roles, SQS Queue, Eventbridge Rules
################################################################################

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.37"

  cluster_name          = module.eks.cluster_name
  enable_v1_permissions = true
  namespace             = "kube-system"

  node_iam_role_use_name_prefix   = false
  node_iam_role_name              = local.name
  create_pod_identity_association = true

}

################################################################################
# Helm charts
################################################################################

resource "helm_release" "karpenter" {
  name                = "karpenter"
  namespace           = "kube-system"
  create_namespace    = true
  repository          = "oci://public.ecr.aws/karpenter"
  chart               = "karpenter"
  version             = "1.14.1"

  values = [
    <<-EOT
    settings:
      clusterName: ${module.eks.cluster_name}
      clusterEndpoint: ${module.eks.cluster_endpoint}
      interruptionQueue: ${module.karpenter.queue_name}
    webhook:
      enabled: false
    EOT
  ]

  lifecycle {
    ignore_changes = [
      repository_password
    ]
  }
}
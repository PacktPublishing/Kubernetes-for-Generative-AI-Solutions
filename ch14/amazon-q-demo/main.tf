/**
 * Main Terraform configuration for EKS GenAI Demo
 * 
 * This configuration sets up an Amazon EKS cluster with:
 * - Dedicated VPC with public/private subnets across 3 AZs
 * - NAT gateway for internet access from private subnets
 * - EKS v1.36 cluster with managed node groups
 * - Standard EKS managed add-ons
 */

provider "aws" {
  region = var.region
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

locals {
  cluster_name = var.cluster_name
  
  # Add cluster tags for proper resource identification
  tags = {
    Environment = "demo"
    Project     = "genai-on-eks"
    Terraform   = "true"
  }
}

# Create VPC using the AWS VPC module
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.21"

  name = "${local.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  # Enable NAT Gateway for outbound internet access from private subnets
  enable_nat_gateway     = true
  single_nat_gateway     = true  # Using a single NAT gateway to reduce costs
  one_nat_gateway_per_az = false

  # Enable DNS support for the VPC
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Add tags required for EKS
  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }

  tags = local.tags
}

# Create EKS cluster using the AWS EKS module
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.37"

  cluster_name    = local.cluster_name
  cluster_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Enable EKS managed add-ons
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  # EKS Managed Node Group(s)
  eks_managed_node_groups = {
    default = {
      name = "node-group-1"

      instance_types = ["m5.large"]
      capacity_type  = "ON_DEMAND"

      min_size     = 2
      max_size     = 5
      desired_size = 2

      # Amazon Linux 2 reached end of support for EKS; AL2023 is the current
      # EKS-optimized AMI family.
      ami_type = "AL2023_x86_64_STANDARD"

      # `remote_access` is only valid when use_custom_launch_template = false.
      # This module builds a custom launch template by default, so SSH access
      # is configured through the launch template's key name instead.
      key_name = var.key_name
    }
  }

  # Grant the identity running `terraform apply` cluster-admin via an EKS access
  # entry. v20 of this module replaced aws-auth configmap management (the old
  # `manage_aws_auth_configmap` argument) with the EKS Access Entry API.
  enable_cluster_creator_admin_permissions = true

  tags = local.tags
}

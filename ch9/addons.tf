module "eks_blueprints_addons" {
  source = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.23.0"
  cluster_name = module.eks.cluster_name
  cluster_endpoint = module.eks.cluster_endpoint
  cluster_version = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn
  enable_aws_load_balancer_controller = true

  # Carried forward from Chapter 6 so overlaying this chapter does not delete the
  # Vertical Pod Autoscaler. The module defaults to a very old chart, so pin one
  # that supports current Kubernetes.
  enable_vpa = true
  vpa = {
    chart_version = "5.0.1"
  }
  enable_secrets_store_csi_driver = true
  enable_secrets_store_csi_driver_provider_aws = true

  secrets_store_csi_driver = {
    chart_version = "1.6.1"
    values = [
      <<-EOT
      syncSecret:
        enabled: true
      # Required by secret-provider-class.yaml's usePodIdentity: "true". The
      # driver has to request a service account token to exchange for Pod
      # Identity credentials, and the chart leaves tokenRequests empty by
      # default. Without this the mount fails with
      # 'CSI token error: serviceAccount.tokens not provided'.
      tokenRequests:
        # pods.eks.amazonaws.com is the audience EKS Pod Identity uses, which is
        # what secret-provider-class.yaml selects with usePodIdentity: "true".
        # sts.amazonaws.com is kept so the same install also works with IRSA.
        - audience: pods.eks.amazonaws.com
        - audience: sts.amazonaws.com
      EOT
    ]
  }
  
  secrets_store_csi_driver_provider_aws = {
    chart_version = "3.1.3"
    values = [
      <<-EOT
      tolerations:
        - operator: Exists
      # From chart 2.0.0 onward the AWS provider bundles secrets-store-csi-driver
      # as a subchart. We install the driver separately above (so that
      # syncSecret can be enabled), so switch the bundled copy off. Leaving it on
      # installs the driver twice and the pre-install hook fails with
      # 'serviceaccounts "secrets-store-csi-driver-upgrade-crds" already exists'.
      secrets-store-csi-driver:
        install: false
      EOT
    ]
  }
  eks_addons = {
    aws-ebs-csi-driver = {
      service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
    }
    metrics-server = {}
    coredns = {}
    kube-proxy = {}
    vpc-cni = {}
    eks-pod-identity-agent = {}
  }
}

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

resource "helm_release" "karpenter" {
  name                = "karpenter"
  namespace           = "kube-system"
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

#---------------------------------------------------------------
# IRSA for EBS CSI Driver
#---------------------------------------------------------------
module "ebs_csi_driver_irsa" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.60"
  role_name_prefix = format("%s-%s", local.name, "ebs-csi-driver-")
  attach_ebs_csi_policy = true
  oidc_providers = {
    main = {
      provider_arn = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

#---------------------------------------------------------------
# GP3 Encrypted Storage Class
#---------------------------------------------------------------
resource "kubernetes_annotations" "disable_gp2" {
  annotations = {
    "storageclass.kubernetes.io/is-default-class" : "false"
  }
  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"
  metadata {
    name = "gp2"
  }
  force = true

  depends_on = [module.eks.eks_cluster_id]
}

resource "kubernetes_storage_class" "default_gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" : "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  allow_volume_expansion = true
  volume_binding_mode    = "WaitForFirstConsumer"
  parameters = {
    fsType    = "ext4"
    encrypted = true
    type      = "gp3"
  }

  depends_on = [kubernetes_annotations.disable_gp2]
}

# Chart renamed from "cost-analyzer" to "kubecost", and the values file moved to
# the kubecost/kubecost repo. Keep this URL's tag and the chart version in step.
data "http" "kubecost_values" {
  url = "https://raw.githubusercontent.com/kubecost/kubecost/v3.2.4/kubecost/values-eks-cost-monitoring.yaml"
}

resource "helm_release" "kubecost" {
  name       = "kubecost"
  repository = "oci://public.ecr.aws/kubecost"
  chart      = "kubecost"
  version    = "3.2.4"
  namespace  = "kubecost"
  create_namespace = true
  values = [data.http.kubecost_values.response_body]
}

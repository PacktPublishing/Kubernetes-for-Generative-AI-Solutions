resource "kubernetes_namespace" "jupyterhub" {
  metadata {
    name = "jupyterhub"
  }
}

provider "random" {}

resource "random_password" "jupyter_pwd" {
  length  = 16
  special = true
  override_special = "_%@"
}

output "jupyter_pwd" {
  value = random_password.jupyter_pwd.result
  sensitive = true
}

module "jupyterhub_single_user_irsa" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.60"

  role_name = "${module.eks.cluster_name}-jupyterhub-single-user-sa"

  role_policy_arns = {
    policy = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess" 
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${kubernetes_namespace.jupyterhub.metadata[0].name}:${module.eks.cluster_name}-jupyterhub-single-user"]
    }
  }
}

resource "kubernetes_service_account_v1" "jupyterhub_single_user_sa" {
  metadata {
    name        = "${module.eks.cluster_name}-jupyterhub-single-user"
    namespace   = kubernetes_namespace.jupyterhub.metadata[0].name
    annotations = { "eks.amazonaws.com/role-arn" : module.jupyterhub_single_user_irsa.iam_role_arn }
  }
  automount_service_account_token = true
}

resource "kubernetes_secret_v1" "jupyterhub_single_user" {
  metadata {
    name      = "${module.eks.cluster_name}-jupyterhub-single-user-secret"
    namespace = kubernetes_namespace.jupyterhub.metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name"      = kubernetes_service_account_v1.jupyterhub_single_user_sa.metadata[0].name
      "kubernetes.io/service-account.namespace" = kubernetes_namespace.jupyterhub.metadata[0].name
    }
  }

  type = "kubernetes.io/service-account-token"
}

data "http" "jupyterhub_values" {
  url = "https://kubernetes-for-genai-models.s3.amazonaws.com/chapter5/jupyterhub-values.yaml"
}

locals {
  jupyterhub_values_template = data.http.jupyterhub_values.response_body
  jupyterhub_values_rendered = replace(
       replace(
         replace(
           local.jupyterhub_values_template,
           "$${jupyter_single_user_sa_name}", kubernetes_service_account_v1.jupyterhub_single_user_sa.metadata[0].name
         ),
         "$${region}", local.region
       ),
       "$${jupyter_pwd}", random_password.jupyter_pwd.result
     )
}

module "eks_data_addons" {
  source  = "aws-ia/eks-data-addons/aws"
  version = "~> 1.38.0"

  oidc_provider_arn = module.eks.oidc_provider_arn

  #---------------------------------------------------------------
  # NVIDIA Device Plugin Add-on
  #---------------------------------------------------------------
  # Time-slicing config carried forward from Chapter 10. Dropping it here
  # would silently turn GPU sharing back off.
  enable_nvidia_device_plugin = true
  nvidia_device_plugin_helm_config = {
    version = "0.20.0"
    name    = "nvidia-device-plugin"
    values = [
      <<-EOT
        gfd:
          enabled: true
        nfd:
          worker:
            tolerations:
              - key: nvidia.com/gpu
                operator: Exists
                effect: NoSchedule
        config:
          name: time-slicing-config
      EOT
    ]
  }
  #---------------------------------------------------------------
  # JupyterHub Add-on
  #---------------------------------------------------------------
  enable_jupyterhub = true
  jupyterhub_helm_config = {
    values = [local.jupyterhub_values_rendered]
    version = "4.4.2"
  }

  # JupyterHub's hub-db-dir PVC asks for gp3, so the StorageClass in addons.tf
  # must exist first. Otherwise the PVC stays Pending and the Helm release
  # fails with "context deadline exceeded".
  depends_on = [kubernetes_storage_class.default_gp3]
}

module "catalog_rag_api_irsa" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.60"

  role_name = "${module.eks.cluster_name}-catalog-sa"

  role_policy_arns = {
    policy = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess" 
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["default:catalog-sa"]
    }
  }
}

resource "kubernetes_service_account_v1" "catalog_rag_api_sa" {
  metadata {
    name        = "catalog-sa"
    namespace   = "default"
    annotations = { "eks.amazonaws.com/role-arn" : module.catalog_rag_api_irsa.iam_role_arn }
  }

  automount_service_account_token = true
}

resource "helm_release" "dcgm_exporter" {
  name       = "dcgm-exporter"
  repository = "https://nvidia.github.io/dcgm-exporter/helm-charts"
  chart      = "dcgm-exporter"
  version    = "4.8.3"
  namespace  = "dcgm-exporter"
  create_namespace = true
  values = [
      <<-EOT
        serviceMonitor:
          enabled: true
        affinity:
          nodeAffinity:
            requiredDuringSchedulingIgnoredDuringExecution:
              nodeSelectorTerms:
              - matchExpressions:
                - key: nvidia.com/gpu.count
                  operator: Exists
        tolerations:
        - key: CriticalAddonsOnly
          operator: Exists
        - effect: NoSchedule
          key: nvidia.com/gpu
          operator: Exists
      EOT
    ]
  depends_on = [
    module.eks
    ]
}

resource "helm_release" "kuberay-operator" {
  name       = "kuberay-operator"
  repository = "https://ray-project.github.io/kuberay-helm/"
  chart      = "kuberay-operator"
  version    = "1.7.0"
  namespace  = "kuberay-operator"
  create_namespace = true
  depends_on = [
    module.eks
  ]
}

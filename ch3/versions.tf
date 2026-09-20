terraform {
  required_version = ">= 1.11"
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = ">= 5.96"
    }
    helm = {
      source = "hashicorp/helm"
      version = ">= 2.17"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
      # Upper bound added: without it this resolves to the 3.x provider, which
      # deprecates kubernetes_namespace and the other resources used here.
      version = ">= 2.36, < 3.0"
    }
  }
}

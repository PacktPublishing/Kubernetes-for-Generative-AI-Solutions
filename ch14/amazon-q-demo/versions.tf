/**
 * Terraform and provider versions
 * 
 * Updated to use specific minimum versions for compatibility
 */

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.63.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      # Upper bound added: without it this resolves to the 3.x provider.
      version = ">= 2.32.0, < 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.15.0"
    }
  }
}

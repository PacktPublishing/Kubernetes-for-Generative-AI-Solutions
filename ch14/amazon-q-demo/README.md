# EKS Cluster for GenAI Models

This Terraform configuration creates an Amazon EKS cluster optimized for running generative AI models.

## Architecture

The infrastructure includes:

- Amazon EKS cluster (v1.36) named "eks-genai-demo" in us-west-2 region
- Dedicated VPC (CIDR 10.0.0.0/16) with public and private subnets across 3 AZs
- Single NAT gateway for internet access from private subnets
- Standard EKS managed add-ons (Amazon VPC CNI, CoreDNS, kube-proxy)
- EKS managed node group with m5.large instances on AL2023

## Prerequisites

- AWS CLI v2, configured with credentials that can create VPC, EKS, and IAM resources
- Terraform >= 1.11
- kubectl, within one minor version of 1.36

> This configuration builds a **separate** cluster with its own VPC and its own
> Terraform state. Run it in its own directory - do not copy it into the shared
> `~/eks-genai` working directory used by Chapters 3-12, or you will end up with
> duplicate `module "vpc"` and `module "eks"` declarations.

## Usage

1. Initialize Terraform:
   ```
   terraform init
   ```

2. Review the execution plan:
   ```
   terraform plan
   ```

3. Apply the configuration:
   ```
   terraform apply
   ```

4. Configure kubectl to connect to your cluster:
   ```
   aws eks update-kubeconfig --region us-west-2 --name eks-genai-demo
   ```

5. Verify the connection:
   ```
   kubectl get nodes
   ```

## Customization

You can customize the deployment by modifying the variables in `variables.tf` or by providing a `.tfvars` file.

## Clean Up

To destroy all resources created by this configuration:
```
terraform destroy
```

## Notes

- The configuration uses a single NAT gateway to reduce costs, but for production environments, consider using one NAT gateway per AZ for higher availability.
- The node group uses m5.large instances by default. For running large GenAI models, use a GPU instance type - `g6` (NVIDIA L4) is what the rest of this book uses; `g4dn`/`p3` are older generations.
- `enable_cluster_creator_admin_permissions = true` grants cluster-admin to the identity that runs `terraform apply`, via an EKS access entry. Other principals need their own access entries.
- `key_name` is optional and defaults to `null`. Set it only if you want SSH access to the nodes.

## Version notes

Three arguments in the original configuration prevented `terraform apply` from
succeeding; all are corrected:

- `manage_aws_auth_configmap` does not exist in EKS module v20 (it was replaced
  by the EKS Access Entry API), so `terraform init` failed with *"An argument
  named `manage_aws_auth_configmap` is not expected here."*
- `ami_type = "AL2_x86_64"` - Amazon Linux 2 is past end of support for EKS and
  has no AMIs for current Kubernetes versions. Now `AL2023_x86_64_STANDARD`.
- `remote_access` is only valid when `use_custom_launch_template = false`, and
  this module creates a custom launch template by default. Replaced with
  `key_name`.

Versions were also updated: Kubernetes 1.32 -> 1.36, EKS module `~> 20.0` ->
`~> 20.37`, VPC module `~> 5.1` -> `~> 5.21`, and the AWS provider constrained to
`~> 5.100` because EKS module v20 pins `aws < 6.0.0`.

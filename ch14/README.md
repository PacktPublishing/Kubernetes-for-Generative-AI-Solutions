# Chapter 14. Wrap Up and Further Readings

The wrap-up chapter. Two self-contained examples accompany it, and unlike
Chapters 3 to 12 neither one layers onto the shared baseline: the Terraform here
builds its own cluster.

| Directory | What it is |
|-----------|-----------|
| [`amazon-q-demo/`](amazon-q-demo) | A standalone EKS cluster written with Amazon Q Developer's help, as an example of AI-assisted infrastructure code |
| [`todo-app/`](todo-app) | A small Flask app with a Dockerfile and Kubernetes manifests, used as a build-and-deploy example |

Each has its own README with full instructions.

## Which cluster do these use?

`amazon-q-demo` creates a **separate** cluster called `eks-genai-demo`, with its
own VPC and its own Terraform state. Run it in its own directory. Do not copy it
over your `~/eks-genai` working directory, or you'll get duplicate `module "vpc"`
and `module "eks"` definitions.

`todo-app` needs no particular cluster. Deploy it to the `eks-genai-demo` cluster
from this chapter, to the baseline cluster from Chapter 3, or to a local `kind`
cluster.

## Version notes

The `amazon-q-demo` Terraform had three problems that stopped `terraform apply`
outright, all fixed:

* **`manage_aws_auth_configmap = true`**: this argument does not exist in EKS
  module v20. Because the module was pinned as `~> 20.0`, it resolved to a v20
  release and `terraform init` failed with *"An argument named
  `manage_aws_auth_configmap` is not expected here."* v20 replaced aws-auth
  ConfigMap management with the EKS Access Entry API, so this is now
  `enable_cluster_creator_admin_permissions = true`.
* **`ami_type = "AL2_x86_64"`**: Amazon Linux 2 is past end of support for EKS
  and has no AMIs for current Kubernetes versions. Now
  `AL2023_x86_64_STANDARD`.
* **`remote_access`**: only valid when `use_custom_launch_template = false`, and
  this module builds a custom launch template by default. Replaced with
  `key_name`, which the launch template accepts.

Also updated: Kubernetes 1.32 → 1.36, EKS module `~> 20.0` → `~> 20.37`, VPC
module `~> 5.1` → `~> 5.21`, and the AWS provider capped at `~> 5.100` (EKS
module v20 requires `aws < 6.0.0`).

For `todo-app`: the base image moved from the end-of-life `python:3.9-slim` to
`python:3.13-slim`, and Flask 2.0.1 / Werkzeug 2.0.1 / gunicorn 20.1.0 were
updated to 3.1.3 / 3.1.8 / 26.2.0. The old pins do not install or run on modern
Python.

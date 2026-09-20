# Chapter 3. Getting Started with K8s in the Cloud

This chapter builds the cluster every later chapter extends: an Amazon VPC, an Amazon EKS
cluster (Kubernetes version 1.36), a Spot managed node group, the core add-ons,
Karpenter, and an Amazon ECR repository for the Chapter 2 container image.

**This is the baseline layer.** Later chapters ship only the files they add or
change and are copied over the top of these files. Work in one directory and keep
one Terraform state for the whole book.

## Files

| File | Purpose |
|------|---------|
| `versions.tf` | Terraform and provider version constraints (used by every chapter) |
| `providers.tf` | `aws`, `kubernetes`, and `helm` providers, authenticated via `aws eks get-token` |
| `locals.tf` | Cluster name, region, VPC CIDR, and AZs |
| `vpc.tf` | VPC with public/private subnets across 3 AZs and a single NAT gateway |
| `eks.tf` | The EKS cluster and a Spot managed node group |
| `addons.tf` | EKS add-ons, AWS Load Balancer Controller, and Karpenter |
| `ecr.tf` | ECR repository for the `my-llama` image |
| `nginx-pod.yaml` | A trivial Pod, to confirm scheduling works |
| `my-llama-svc.yaml` | A `LoadBalancer` Service fronting the Llama deployment |

Defaults live in `locals.tf`: cluster `eks-demo`, region `us-west-2`, VPC
`10.0.0.0/16`. The Kubernetes version (`1.36`) is set in the `eks` module block
in `eks.tf`.

## Prerequisites

AWS credentials with permission to create VPC, EKS, IAM, and ECR resources:

```bash
aws sts get-caller-identity
```

### Check for name collisions first

Several resources here are named after the cluster (`eks-demo`) and must be
unique per account and Region. If a previous run was not fully destroyed, or
someone else in the account already used the name, `terraform apply` fails
part-way through. `terraform plan` does not catch this, because the conflict only
surfaces when AWS rejects the create call.

```bash
aws eks describe-cluster --region us-west-2 --name eks-demo
aws ecr describe-repositories --region us-west-2 --repository-names my-llama
aws logs describe-log-groups --region us-west-2 --log-group-name-prefix /aws/eks/eks-demo
aws kms list-aliases --region us-west-2 --query "Aliases[?AliasName=='alias/eks/eks-demo']"
aws iam list-roles --query "Roles[?starts_with(RoleName,'eks-demo')].RoleName"
```

Anything that comes back means a collision. The errors look like this:

```
Error: creating KMS Alias (alias/eks/eks-demo): AlreadyExistsException
Error: creating CloudWatch Logs Log Group (/aws/eks/eks-demo/cluster): ResourceAlreadyExistsException
Error: creating ECR Repository (my-llama): RepositoryAlreadyExistsException
```

The simplest fix is to pick a different cluster name in `locals.tf`, which
renames all of them at once:

```hcl
name = "eks-demo-2"
```

Otherwise delete the leftovers. Note that an orphaned log group and KMS alias can
outlive the cluster they belonged to, so they persist after a `terraform destroy`
that did not finish cleanly.

If `10.0.0.0/16` is already taken by a VPC you plan to peer with, change
`vpc_cidr` in `locals.tf` too. Overlapping CIDRs are legal in isolated VPCs, so
this only matters if you intend to connect them.

## Deploy

`$REPO` points at your clone of this repository; see
[Getting the code](../README.md#getting-the-code) if you have not set it.

```bash
mkdir -p ~/eks-genai && cd ~/eks-genai
cp $REPO/ch3/*.tf .

terraform init
terraform apply
```

Expect 15 to 25 minutes. The long poles are the EKS control plane (about 9
minutes), then the managed node group, and then the CoreDNS add-on, which waits
for nodes before it can finish. Then wire up `kubectl` using the command
Terraform prints:

```bash
aws eks --region us-west-2 update-kubeconfig --name eks-demo
kubectl get nodes
```

## Verify

```bash
kubectl get nodes -o wide
kubectl get pods -n kube-system
kubectl get deploy -n kube-system aws-load-balancer-controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter
```

You should see two Spot nodes, CoreDNS, kube-proxy, the VPC CNI, the Pod Identity
agent, the load balancer controller, and Karpenter.

Smoke-test scheduling:

```bash
kubectl apply -f $REPO/ch3/nginx-pod.yaml
kubectl get pod nginx-pod -w
kubectl delete -f $REPO/ch3/nginx-pod.yaml
```

## Push the Chapter 2 image and expose it

`terraform output ecr_push_cmds` prints the exact push commands for your account:

```bash
terraform output -raw ecr_push_cmds
```

Then deploy the image and expose it. `my-llama-svc.yaml` selects pods labelled
`app: my-llama`, so create the deployment with a matching label:

```bash
ECR_URI=$(aws ecr describe-repositories --region us-west-2 \
  --repository-names my-llama --query 'repositories[0].repositoryUri' --output text)

kubectl create deployment my-llama --image=$ECR_URI
kubectl apply -f $REPO/ch3/my-llama-svc.yaml
kubectl get svc my-llama-svc -w   # wait for EXTERNAL-IP
```

The Service is annotated for an internet-facing NLB, which the AWS Load Balancer
Controller provisions.

## Notes on this configuration

* **Spot capacity.** The node group requests several instance families
  (`m5`/`m6i`/`m6a`/`m7i`/`m7a`) so Spot has room to find capacity.
* **Cluster access.** `enable_cluster_creator_admin_permissions = true` grants
  the identity that ran `terraform apply` cluster-admin through an EKS access
  entry. Anyone else needs their own access entry.
* **Public endpoint.** `cluster_endpoint_public_access = true` keeps the tutorial
  simple. Restrict or disable it for anything real.
* **`karpenter.sh/discovery` tags.** Applied to subnets and the node security
  group so Karpenter can find them. Chapter 6 relies on these.
* **Karpenter appears here, not in Chapter 6.** `addons.tf` installs it so the
  baseline is complete. Chapter 6 ships its own `addons.tf` and `karpenter.tf`
  and replaces both files. Do not stack the two Karpenter definitions.

## Version notes

* Kubernetes 1.36 (the current EKS default), set via `cluster_version` in
  `eks.tf`.
* Karpenter chart 1.14.1. Chart 1.13 or newer is required for Kubernetes 1.36.
* `versions.tf` keeps the book's original `>= 5.96` / `>= 2.17` constraints for
  the AWS and Helm providers, because the modules already cap both below their
  next major. The one added bound is `< 3.0` on the Kubernetes provider. See the
  root README for the reasoning.
* EKS add-ons are declared without explicit versions (`coredns = {}`), so EKS
  picks the default build for the cluster version. On 1.36 that resolved to
  CoreDNS `v1.14.3-eksbuild.24`, kube-proxy `v1.36.0-eksbuild.25`, VPC CNI
  `v1.23.1-eksbuild.1`, and Pod Identity Agent `v1.4.0-eksbuild.2`.
* The Spot node group spreads across instance families, so the two nodes will not
  usually match each other. Expect a mix such as one `m6a.large` and one
  `m7i.large`, depending on what Spot has available.

## Clean up

```bash
kubectl delete -f $REPO/ch3/my-llama-svc.yaml   # remove the NLB first
terraform destroy
```

Delete `LoadBalancer` Services before `terraform destroy`. Otherwise the ELB
keeps the subnets in use and the VPC deletion hangs.

If you reached Chapter 6, delete the Karpenter `NodePool` resources too and wait
for the `NodeClaims` to drain. Karpenter's instances are not in Terraform state,
so leftover nodes block the teardown.

One more thing that can fail the destroy: **`ecr.tf` has no `force_delete`**, so
if you pushed an image the teardown stops with `RepositoryNotEmptyException`.
Empty the repository first:

```bash
aws ecr batch-delete-image --region us-west-2 --repository-name my-llama \
  --image-ids "$(aws ecr list-images --region us-west-2 \
    --repository-name my-llama --query 'imageIds[*]' --output json)"
```

Or add `force_delete = true` to the `aws_ecr_repository` resource.

If subnet deletion stalls for many minutes, something outside Terraform still has
an elastic network interface in the VPC. List them and find the owner:

```bash
aws ec2 describe-network-interfaces --region us-west-2 \
  --filters "Name=vpc-id,Values=<vpc-id>" \
  --query 'NetworkInterfaces[].[NetworkInterfaceId,InterfaceType,Description]' --output text
```

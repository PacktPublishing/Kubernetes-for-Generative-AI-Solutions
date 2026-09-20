# Chapter 6. Deploying GenAI on K8s: Scaling Best Practices

Three layers of autoscaling: the Horizontal Pod Autoscaler for replica count, the
Vertical Pod Autoscaler for per-pod requests, and Karpenter for nodes.

## Layers

`$REPO` points at your clone of this repository; see
[Getting the code](../README.md#getting-the-code) if you have not set it.

```bash
cd ~/eks-genai
cp $REPO/ch3/*.tf .    # baseline (skip if you still have it)
cp $REPO/ch6/*.tf . && rm -f karpenter.tf    # this chapter (karpenter.tf is reference only)
terraform init && terraform apply
```

`ch6/addons.tf` and `ch6/eks.tf` replace whichever versions you already have.

> **Do not copy `karpenter.tf`.** It is reference only: it holds the same
> Karpenter blocks that `addons.tf` already declares, separated out because this
> is the chapter that walks through them. Copying both gives you
> `Error: Duplicate module call`, and because Chapters 7, 9 and 12 also declare
> Karpenter in their `addons.tf`, the duplicate follows you for the rest of the
> book.
>
> This chapter's `addons.tf` is the ch5 set plus the Vertical Pod Autoscaler. It
> keeps Karpenter, the EBS CSI driver and the `gp3` StorageClass, so overlaying it
> does not delete the storage Qdrant and JupyterHub are using.

## Files

| File | Purpose |
|------|---------|
| `addons.tf` | The ch5 add-on set **plus** the Vertical Pod Autoscaler |
| `eks.tf` | Managed node group with the GPU group commented out, so Karpenter provisions GPU nodes instead |
| `karpenter.tf` | Reference only: the Karpenter blocks from `addons.tf`, shown on their own |
| `eks-np.yaml` | Karpenter `NodePool` + `EC2NodeClass` for general-purpose `m` instances |
| `eks-gpu-np.yaml` | Karpenter `NodePool` for `g6` GPU instances, tainted `nvidia.com/gpu` |
| `eks-gpu-nc.yaml` | `EC2NodeClass` for the GPU pool (encrypted 100 GiB gp3 root volume) |
| `chatbot-ui-hpa.yaml` | HPA on the chat UI: 1 to 5 replicas at 70% CPU |
| `chatbot-ui-vpa.yaml` | VPA on the chat UI in `Auto` mode |

## Deploy

```bash
terraform apply
kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter
kubectl get pods -n vpa
kubectl get deploy -n kube-system metrics-server
```

Then create the Karpenter pools:

```bash
kubectl apply -f eks-np.yaml
kubectl apply -f eks-gpu-nc.yaml
kubectl apply -f eks-gpu-np.yaml
kubectl get nodepools,ec2nodeclasses
```

The `EC2NodeClass` resources discover subnets and security groups by the
`karpenter.sh/discovery: eks-demo` tag and use the node IAM role named
`eks-demo`, both created by the Terraform. If you renamed the cluster in
`locals.tf`, update the tag values and `role` in all three YAML files to match.

## Try the autoscalers

### Karpenter

```bash
kubectl create deployment inflate --image=public.ecr.aws/eks-distro/kubernetes/pause:3.7
kubectl set resources deployment inflate --requests=cpu=1
kubectl scale deployment inflate --replicas=8

kubectl get nodeclaims -w                    # Karpenter creating capacity
kubectl logs -f -n kube-system -l app.kubernetes.io/name=karpenter
```

Scale back down and watch the nodes go away. The pools use
`consolidationPolicy: WhenEmpty` with a 120s wait:

```bash
kubectl delete deployment inflate
kubectl get nodeclaims -w
```

### HPA

Requires the chat UI from Chapter 5 (`chatbot-ui-deployment`):

```bash
kubectl apply -f chatbot-ui-hpa.yaml
kubectl get hpa chatbot-ui-hpa -w
```

If the `TARGETS` column shows `<unknown>`, metrics-server is not ready yet
(`kubectl top pods` should work first), or the deployment has no CPU *requests*.
The HPA computes utilization as a percentage of requests, so with none it cannot
scale.

### VPA

```bash
kubectl apply -f chatbot-ui-vpa.yaml
kubectl describe vpa chatbot-ui-vpa       # look at the recommendations
```

`updateMode: "Auto"` means the VPA **evicts and recreates pods** to apply new
requests. Use `Off` if you only want recommendations. Do not point an HPA and a
VPA at the same CPU metric on the same workload, because they will fight.

## Version notes

* Karpenter chart 1.14.1, up from 1.0.2. Chart 1.13 or newer is required for
  Kubernetes 1.36. The older pin supports only up to 1.30.
* The manifests already use the stable Karpenter v1 APIs (`karpenter.sh/v1`,
  `karpenter.k8s.aws/v1`), so no CRD migration is needed.
* The VPA chart is pinned to 5.0.1 (app 1.7.1). The blueprints-addons module
  still defaults to a much older chart that does not work on current Kubernetes.
* `amiSelectorTerms: [{alias: al2023@latest}]` tracks the latest AL2023 AMI.
  Pin a specific version for production so nodes don't change under you.
* The GPU `NodePool` hard-codes `us-west-2a/b/c`. Update the zones if you
  changed the region.

## Clean up

```bash
kubectl delete -f chatbot-ui-vpa.yaml -f chatbot-ui-hpa.yaml
kubectl delete -f eks-gpu-np.yaml -f eks-gpu-nc.yaml -f eks-np.yaml
kubectl get nodeclaims       # wait until empty
terraform destroy
```

Delete the `NodePool` resources and wait for the `NodeClaims` to drain **before**
`terraform destroy`. Karpenter-managed instances are not in Terraform state, so
leftover nodes will block the VPC teardown.

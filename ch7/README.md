# Chapter 7. Deploying GenAI on K8s: Cost Optimization Best Practices

Adds Kubecost to the cluster so you can attribute GenAI spend by namespace,
workload, and label, which matters most for the GPU nodes.

## Layers

`$REPO` points at your clone of this repository; see
[Getting the code](../README.md#getting-the-code) if you have not set it.

```bash
cd ~/eks-genai
cp $REPO/ch3/*.tf .    # baseline
cp $REPO/ch5/*.tf .    # GPU nodes, JupyterHub, Qdrant
cp $REPO/ch7/*.tf .    # this chapter
terraform init && terraform apply
```

`ch7/addons.tf` replaces `ch5/addons.tf`. It is the same file with Kubecost
appended. Chapter 5 is included because the interesting cost data comes from the
GPU node group and the workloads on it.

## Files

| File | Purpose |
|------|---------|
| `addons.tf` | Everything from ch5 plus the Kubecost Helm release and its EKS-tuned values |

## Deploy

```bash
terraform apply
kubectl get pods -n kubecost
```

Give it 5 to 10 minutes to accumulate data, then open the UI:

```bash
kubectl port-forward -n kubecost svc/kubecost-frontend 9090:9090
```

Open <http://localhost:9090>.

> The `kubecost` chart splits itself into several Services, and the UI is on
> `kubecost-frontend` (port 9090). There is no `kubecost-cost-analyzer` Service
> any more, that was the old `cost-analyzer` chart. List them with
> `kubectl get svc -n kubecost` if the port-forward fails.

Allocation data does not appear immediately. Kubecost needs several minutes of
scrapes before `/model/allocation` returns anything, so an empty Allocation view
right after install is normal rather than a misconfiguration.

## What to look at

* **Allocation**: cost by namespace. The `jupyterhub` and `default` namespaces
  carry the GPU workloads.
* **Assets**: the underlying EC2, EBS, and load balancer spend. GPU instances
  dominate.
* **Savings**: idle GPU capacity and over-requested workloads. This is the
  chapter's real payoff: a `g6.2xlarge` sitting idle still bills by the hour.

Cross-check against reality:

```bash
kubectl get nodes -L node.kubernetes.io/instance-type,karpenter.sh/capacity-type
```

## Version notes

Kubecost moved since the book was written, and both changes were breaking:

* **The chart was renamed** from `cost-analyzer` to `kubecost`. The old
  `cost-analyzer` chart is frozen at 2.9.6.
* **The values file moved.** The configuration previously fetched
  `values-eks-cost-monitoring.yaml` from
  `kubecost/cost-analyzer-helm-chart` on the `develop` branch. That repository is
  now `kubecost/kubecost` and the path changed, so the old URL returns **404** and
  `terraform apply` fails while reading the data source.

The updated `addons.tf` pins both together so they cannot drift:

```hcl
locals {
  kubecost_version = "3.2.4"
}

data "http" "kubecost_values" {
  url = "https://raw.githubusercontent.com/kubecost/kubecost/v${local.kubecost_version}/kubecost/values-eks-cost-monitoring.yaml"
}

resource "helm_release" "kubecost" {
  chart   = "kubecost"
  version = local.kubecost_version
  ...
}
```

The values file configures Kubecost for EKS cost monitoring, which reads AWS
pricing directly. Full Cost and Usage Report integration needs extra IAM setup
that this chapter does not cover.

## Clean up

Kubecost is part of the Terraform, so `terraform destroy` removes it. To drop
just Kubecost, delete the `helm_release` and `data "http"` blocks and re-apply, or:

```bash
helm uninstall kubecost -n kubecost && kubectl delete namespace kubecost
```

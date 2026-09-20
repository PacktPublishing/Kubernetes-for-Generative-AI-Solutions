# Chapter 10. Optimizing GPU Resources in K8s for GenAI Applications

A `g6.2xlarge` has one L4 GPU, and a small model like Llama 3.2 1B uses a
fraction of it. This chapter packs multiple pods onto one GPU using
**time-slicing**, and covers MIG and MPS as alternatives.

## Layers

`$REPO` points at your clone of this repository; see
[Getting the code](../README.md#getting-the-code) if you have not set it.

```bash
cd ~/eks-genai
cp $REPO/ch3/*.tf .    # baseline
cp $REPO/ch5/*.tf .    # GPU nodes, JupyterHub, Qdrant
cp $REPO/ch10/*.tf .   # this chapter
terraform init && terraform apply
```

`ch10/aiml-addons.tf` replaces `ch5/aiml-addons.tf`.

## Files

| File | Purpose |
|------|---------|
| `aiml-addons.tf` | NVIDIA device plugin configured for time-slicing (plus GFD/NFD), JupyterHub, and DCGM exporter |
| `nvidia-ts.yaml` | The `time-slicing-config` ConfigMap: 10 replicas per GPU |
| `llama32-inf/` | Llama 3.2 1B FastAPI inference service, 5 replicas sharing GPUs |

## Deploy

Order matters. The device plugin references a ConfigMap by name
(`config.name: time-slicing-config`), so create it **before** the plugin starts,
in the namespace the plugin runs in:

```bash
kubectl create namespace nvidia-device-plugin
kubectl apply -f nvidia-ts.yaml
terraform apply
```

If you applied Terraform first, the plugin pod will crash-loop until the
ConfigMap exists; restart it afterwards:

```bash
kubectl rollout restart -n nvidia-device-plugin ds/nvidia-device-plugin
```

## Verify time-slicing

A single physical GPU should now advertise 10 allocatable units:

```bash
kubectl get nodes -o json | jq -r '
  .items[] | select(.status.allocatable["nvidia.com/gpu"]) |
  "\(.metadata.name)  gpus=\(.status.allocatable["nvidia.com/gpu"])"'
```

`gpus=10` on a one-GPU node means it worked. On a multi-GPU instance you get 10
per physical GPU, so a 4-GPU `g6.12xlarge` reports 40. The node labels from GPU Feature
Discovery confirm the strategy:

```bash
kubectl get nodes -o json | jq -r '
  .items[].metadata.labels | to_entries[] |
  select(.key|test("nvidia.com/(gpu.count|gpu.product|gpu.sharing|mig)")) |
  "\(.key)=\(.value)"' | sort -u
```

## Deploy the shared-GPU workload

```bash
cd llama32-inf
docker build -t my-llama32 .
# push to ECR, then set the image in llama32-deploy.yaml
kubectl apply -f llama32-deploy.yaml
kubectl get pods -l app.kubernetes.io/name=my-llama32 -o wide
```

The deployment asks for `nvidia.com/gpu: 2` per pod across 5 replicas, 10 units
total, exactly the time-sliced capacity of one GPU. All five pods should schedule
onto a single GPU node.

> **If Karpenter is provisioning your GPU nodes, watch the instance size.**
> From Chapter 6 onward there is no static GPU node group, and Karpenter sizes
> nodes from the *physical* GPU count reported by the instance type. It has no
> idea the device plugin will multiply that by ten. Asking for 10 GPU units made
> it pick a `g6.12xlarge` (4 L4s, so 40 time-sliced units) where a single
> `g6.2xlarge` (1 L4, 10 units) would have been enough, at roughly three times
> the hourly cost. Either pin the pool to one instance type:
>
> ```yaml
> - key: "node.kubernetes.io/instance-type"
>   operator: In
>   values: ["g6.2xlarge"]
> ```
>
> or lower `nvidia.com/gpu` per pod so the total fits one physical GPU.

Test it:

```bash
kubectl port-forward svc/my-llama32-svc 8000:80
curl -s -X POST localhost:8000/generate \
  -H 'Content-Type: application/json' \
  -d '{"prompt":"Explain Kubernetes in one sentence."}' | jq .
```

Watch actual GPU utilization while you drive load:

```bash
kubectl port-forward -n dcgm-exporter svc/dcgm-exporter 9400:9400
curl -s localhost:9400/metrics | grep -E '^DCGM_FI_DEV_(GPU_UTIL|FB_USED)'
```

## Time-slicing vs MIG vs MPS

| | Time-slicing | MIG | MPS |
|---|---|---|---|
| Isolation | None, contexts interleave | Hardware-partitioned memory and SMs | Shared context, no memory isolation |
| Hardware | Any NVIDIA GPU | A100, H100, and newer data-center GPUs | Any NVIDIA GPU |
| On `g6` (L4) | ✅ what this chapter uses | ❌ not supported | ✅ supported |
| Best for | Bursty, small models; dev and notebooks | Predictable multi-tenant serving | Many small concurrent contexts |

Time-slicing gives no memory isolation: one pod can OOM the GPU and take its
neighbours down with it. `replicas: 10` is aggressive; it is meant to show the
mechanism, not to be a production setting.

MIG needs MIG-capable hardware (`p4d`, `p5`, `g5g` do not qualify; A100/H100 do)
and a different plugin config:

```yaml
migStrategy: single     # or "mixed"
```

MPS is configured through `sharing.mps` in the device plugin instead of
`sharing.timeSlicing`.

## Version notes

* NVIDIA device plugin 0.20.0 (was 0.17.1). The `gfd`, `nfd`, and `config.name`
  value keys used here are unchanged in this release.
* DCGM exporter is now pinned to 4.8.3 rather than tracking whatever the chart
  repository serves.
* **`llama32-inf/Dockerfile` had two real bugs, both fixed:**
  * It ran `COPY main2.py /app/main.py`, but the file in this directory is
    `main.py`, so the build failed outright.
  * It ran `pip install` against the system Python on Ubuntu 24.04, which refuses
    it under PEP 668 (`externally-managed-environment`). It now builds a
    virtualenv, matching the Chapter 5 images.
* The base image moved to `nvidia/cuda:12.8.1-runtime-ubuntu24.04` for
  consistency with Chapter 5, and `transformers` is pinned to the 4.x line.
* `nvidia-ts.yaml` hard-codes `namespace: nvidia-device-plugin`. If you install
  the plugin elsewhere, change it to match.

## Clean up

```bash
kubectl delete -f llama32-inf/llama32-deploy.yaml
kubectl delete -f nvidia-ts.yaml
terraform destroy
```

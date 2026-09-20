# Chapter 11. GenAIOps: Creating GenAI Automation Pipeline

The code for this chapter is the KubeRay half of the pipeline: it runs Llama 3.1
8B Instruct behind Ray Serve and vLLM on KubeRay, with Ray Serve autoscaling
replicas and the Ray autoscaler adding GPU worker pods.

## Layers

`$REPO` points at your clone of this repository; see
[Getting the code](../README.md#getting-the-code) if you have not set it.

```bash
cd ~/eks-genai
cp $REPO/ch3/*.tf .    # baseline
cp $REPO/ch5/*.tf .    # GPU nodes, JupyterHub, Qdrant
cp $REPO/ch11/*.tf .   # this chapter
terraform init && terraform apply
```

`ch11/aiml-addons.tf` replaces `ch5/aiml-addons.tf` and adds the KubeRay operator
and DCGM exporter.

## Files

| File | Purpose |
|------|---------|
| `aiml-addons.tf` | NVIDIA device plugin, JupyterHub, DCGM exporter, and the KubeRay operator |
| `ray-service-vllm.yaml` | `RayService` serving Llama 3.1 8B Instruct through Ray Serve LLM |

## Prerequisites

* A Hugging Face token **with access granted to `meta-llama/Llama-3.1-8B-Instruct`**
  (the repo is gated, so request access on the model page first).
* GPU capacity for at least one `g6.2xlarge`.

```bash
kubectl create secret generic hf-secret \
  --from-literal=hf_api_token=hf_xxxxxxxxxxxxxxxx
```

The secret name and key (`hf-secret` / `hf_api_token`) must match the manifest.

## Deploy

```bash
terraform apply
kubectl get pods -n kuberay-operator
kubectl get crd | grep ray.io
```

Then the service:

```bash
kubectl apply -f ray-service-vllm.yaml
kubectl get rayservice llama-31-8b -w
```

First start is slow, roughly 10 to 20 minutes. The image is large and the model
weights (~16 GB) download from Hugging Face before vLLM finishes loading. Watch
progress:

```bash
kubectl get pods -l ray.io/cluster
kubectl logs -f -l ray.io/node-type=worker -c llm
```

`kubectl get rayservice` should eventually report both
`Ready` service status and a running Serve application.

## Test the API

Ray Serve LLM exposes an **OpenAI-compatible** API:

```bash
kubectl port-forward svc/llama-31-8b-serve-svc 8000:8000

curl -s localhost:8000/v1/models | jq .

curl -s localhost:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "meta-llama/Llama-3.1-8B-Instruct",
    "messages": [{"role":"user","content":"Explain Kubernetes in two sentences."}],
    "max_tokens": 128
  }' | jq -r '.choices[0].message.content'
```

The Ray dashboard shows deployment replicas, queue depth, and per-replica latency:

```bash
kubectl port-forward svc/llama-31-8b-head-svc 8265:8265
# http://localhost:8265 -> Serve tab
```

## Autoscaling

Two independent loops:

* **Ray Serve** scales `VLLMDeployment` replicas between `min_replicas: 1` and
  `max_replicas: 5`, targeting `target_ongoing_requests: 32`.
* **The Ray autoscaler** (`enableInTreeAutoscaling: true`) adds worker pods when
  replicas have nowhere to run, between `minReplicas: 1` and `maxReplicas: 5`.
* **Karpenter** (Chapter 6) then adds GPU nodes for those pending pods.

Drive some concurrent load and watch all three react:

```bash
for i in $(seq 1 60); do
  curl -s localhost:8000/v1/chat/completions \
    -H 'Content-Type: application/json' \
    -d '{"model":"meta-llama/Llama-3.1-8B-Instruct","messages":[{"role":"user","content":"hi"}],"max_tokens":64}' \
    -o /dev/null &
done; wait

kubectl get pods -l ray.io/node-type=worker -w
```

## Version notes

This manifest was substantially reworked, because the original could not deploy
at all:

* **The referenced sample no longer exists.** The old config set
  `working_dir` to a KubeRay `master` zip and
  `import_path: ray-operator.config.samples.vllm.serve:model`. Upstream deleted
  that generic-GPU vLLM sample (only the TPU variant remains), so Ray Serve could
  never import the application.
* **`rayproject/ray-ml` images are no longer published.** The old
  `rayproject/ray-ml:2.33.0.914af0-py311` tag is from a discontinued image line.
  The manifest now uses `rayproject/ray-llm:2.58.0-py312-cu130`, which ships vLLM
  in the image, so the `pip: ["vllm==0.5.4"]` runtime install is gone and pods
  start much faster.
* **`ray.serve.llm:build_openai_app`** is the current way to serve an LLM on Ray
  Serve, and it gives you an OpenAI-compatible API for free.
* KubeRay operator pinned to 1.7.0, DCGM exporter to 4.8.3.

**Driver requirement:** the `cu130` image needs an NVIDIA driver >= 580. The EKS
1.36 AL2023 NVIDIA AMI ships 580.178.04, so the `g6` nodes in this book work
as-is. On an older AMI, either update the node AMI or pick a `cu128` Ray image.

To pin scheduling to a specific accelerator, add `accelerator_type: L4` (for
`g6`) under the `llm_configs` entry. It is omitted here so the manifest also
works on `g5`/A10G nodes.

## Troubleshooting

| Symptom | Cause |
|---------|-------|
| Worker pod `Pending` | No GPU node available. Check `kubectl get nodeclaims` and Spot capacity |
| `401`/`403` pulling the model | Token lacks access to the gated `meta-llama` repo |
| `CUDA error: forward compatibility` | Node driver older than 580; see above |
| OOM during load | Lower `gpu_memory_utilization` or `max_model_len` |
| RayService stuck `Preparing` | Still downloading weights. Check worker logs |

## Clean up

```bash
kubectl delete -f ray-service-vllm.yaml
kubectl delete secret hf-secret
terraform destroy
```

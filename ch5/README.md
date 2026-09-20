# Chapter 5. Getting Started with GenAI on K8s: Chatbot Example

The biggest chapter in the book. It extends the Chapter 3 baseline with GPU nodes,
JupyterHub, a Qdrant vector database, and four containerized applications: a
Llama fine-tuning Job, a fine-tuned inference API, a RAG API, and a Gradio chat UI.

## Layers

`$REPO` points at your clone of this repository; see
[Getting the code](../README.md#getting-the-code) if you have not set it.

```bash
cd ~/eks-genai
cp $REPO/ch3/*.tf .    # baseline (skip if you still have it)
cp $REPO/ch5/*.tf .    # this chapter
terraform init && terraform apply
```

`ch5/eks.tf`, `ch5/addons.tf`, and `ch5/ecr.tf` replace the ch3 versions;
`aiml-addons.tf`, `model-assets.tf`, and `qdrant.tf` are new. The overlay adds
resources without deleting any, so a `plan` over the ch3 baseline reports
`0 to destroy`.

Two things to expect on this apply:

* **The CPU node group is replaced, which takes about 16 minutes.** `ch5/eks.tf`
  adds `vpc_security_group_ids` to the `eks-mng` group, and changing it rewrites
  the launch template, so EKS rolls the nodes. Pods running from Chapter 3 are
  evicted and rescheduled. This is normal; wait it out.
* **The GPU node needs Spot capacity for `g6.2xlarge`.** Check before you start:

  ```bash
  aws ec2 describe-spot-price-history --region us-west-2 \
    --instance-types g6.2xlarge --product-descriptions 'Linux/UNIX' \
    --start-time "$(date -u -d '-1 hour' +%FT%TZ)" \
    --query 'SpotPriceHistory[].[AvailabilityZone,SpotPrice]' --output text | sort -u
  ```

  Expect roughly $0.65 to $0.85 per hour for the GPU node, which puts the whole
  cluster near $1 per hour from this chapter onward. Check current pricing for
  your Region before you start.

## Files

### Infrastructure

| File | Purpose |
|------|---------|
| `eks.tf` | Adds a `g6.2xlarge` GPU node group and the fine-tuning job's IRSA role |
| `addons.tf` | Adds the EBS CSI driver, metrics-server, and a default encrypted `gp3` StorageClass |
| `aiml-addons.tf` | NVIDIA device plugin, JupyterHub, and the RAG app's IRSA role |
| `qdrant.tf` | Qdrant vector database via Helm |
| `model-assets.tf` | S3 bucket for fine-tuned model artifacts |
| `ecr.tf` | ECR repositories: `my-llama`, `my-llama-finetuned`, `rag-app` |

### Applications

| Directory | What it is |
|-----------|-----------|
| `llama-finetuning/` | QLoRA fine-tuning Job; uploads the adapter to S3 |
| `inference/` | FastAPI server for the fine-tuned model (`POST /generate`) |
| `rag-app/` | FastAPI RAG service over Qdrant + OpenAI (`POST /generate`, `POST /load_data`) |
| `bedrock-rag-app/` | The same RAG service backed by Amazon Bedrock instead of OpenAI |
| `chatbot/` | Gradio UI that routes to the RAG API or the fine-tuned model |

## Prerequisites

* The Chapter 3 baseline, applied.
* **GPU capacity.** The GPU node group requests `g6.2xlarge` on Spot. If it never
  becomes ready you are out of Spot capacity. Switch `capacity_type` to
  `ON_DEMAND` in `eks.tf`, or pick another region.
* **A Hugging Face token** with access to the gated `meta-llama` repositories.
* **An OpenAI API key** for the RAG app (or use `bedrock-rag-app` instead).

## Deploy

### 1. Infrastructure

```bash
terraform apply
kubectl get nodes -L nvidia.com/gpu.present
kubectl get pods -n nvidia-device-plugin
kubectl get pods -n qdrant
kubectl get storageclass          # gp3 should be the default
```

Confirm the GPU is actually advertised before going further:

```bash
kubectl get nodes -o json \
  | jq -r '.items[] | "\(.metadata.name)\tGPUs=\(.status.allocatable["nvidia.com/gpu"] // 0)"'
```

### 2. JupyterHub

```bash
terraform output -raw jupyter_pwd     # login password
kubectl port-forward -n jupyterhub svc/proxy-public 8080:80
```

Open <http://localhost:8080> and sign in as `k8s-admin1` or `k8s-user1` with that
password. Authentication is `DummyAuthenticator`, which is fine for a lab and
never for anything shared.

### 3. Fine-tune the model

```bash
cd llama-finetuning
docker build -t my-llama-finetuning .
# push to the my-llama-finetuned repo; see: terraform output -raw my_llama_finetuned_ecr_push_cmds
```

Edit `llama-finetuning-job.yaml` and replace the three placeholders: the image,
`MODEL_ASSETS_BUCKET` (from `terraform output my_llama_bucket`), and
`HUGGING_FACE_HUB_TOKEN`. Then:

```bash
kubectl apply -f llama-finetuning-job.yaml
kubectl logs -f job/my-llama-job
```

The Job runs on the GPU node via the `llama-fine-tuning-sa` service account,
which has S3 write access, and uploads the adapter to a timestamped prefix
(`llama-<YYYYmmdd-HHMMSS>/`).

> Put the token in a Secret rather than the manifest. Chapter 9 replaces this
> plaintext environment variable with Secrets Manager and the Secrets Store CSI
> driver.

### 4. Serve the fine-tuned model

`inference/Dockerfile` bakes the adapter into the image, so download it first:

```bash
cd ../inference
aws s3 sync s3://$(terraform output -raw my_llama_bucket)/llama-<timestamp>/ ./model-assets/
docker build -t my-llama-finetuned .
# push, then set the image in finetuned-inf-deploy.yaml
kubectl apply -f finetuned-inf-deploy.yaml
```

### 5. RAG app and chat UI

Seed Qdrant from the book's published snapshot:

```bash
cd ../rag-app
kubectl apply -f qdrant-restore-job.yaml
kubectl logs -f job/qdrant-restore-job
```

Then build, push, and deploy the RAG API. Set the image and `OPENAI_API_KEY` in
`rag-deploy.yaml` first:

```bash
docker build -t rag-app . && kubectl apply -f rag-deploy.yaml
cd ../chatbot && kubectl apply -f chatbot-deploy.yaml
kubectl get svc chatbot-ui-service -w    # wait for EXTERNAL-IP
```

The chat UI is a `LoadBalancer` Service on port 80 forwarding to Gradio on 7860.
It offers two assistants: **Shopping** (the RAG API) and **Loyalty Program** (the
fine-tuned model).

## Verify

```bash
kubectl get pods
curl -s -X POST http://<chatbot-elb>/  -o /dev/null -w '%{http_code}\n'

# RAG API directly
kubectl port-forward svc/rag-app-service 8000:80
curl -s -X POST localhost:8000/generate \
  -H 'Content-Type: application/json' \
  -d '{"prompt":"Do you sell running shoes?"}' | jq .
```

## Version notes

* **Python images are pinned to `python:3.13-slim`.** The bare `python:slim` tag
  now resolves to Python 3.14, where the LangChain 0.3 / pydantic stack fails to
  evaluate forward-referenced type annotations. This is a hard failure at import.
* **LangChain is pinned to the 0.3 line.** `rag-app/main.py` imports
  `langchain.memory`, `langchain.text_splitter`, and `RetrievalQA`, all of which
  LangChain 1.x moved or removed.
* **`httpx` is now declared explicitly** in `rag-app/requirements.txt`. The code
  imports it directly but previously relied on it arriving transitively.
* **transformers is held at 4.x** in the fine-tuning and inference images; v5
  changed the `Trainer` API these scripts use.
* NVIDIA device plugin 0.20.0, JupyterHub 4.4.2, Qdrant 1.19.1.
* `bedrock-rag-app` calls `boto3.client('bedrock-runtime')` with no explicit
  region, so the pod needs `AWS_REGION`/`AWS_DEFAULT_REGION` set (or an IMDS
  region). It also needs an IAM role with `bedrock:InvokeModel` and model access
  enabled in the Bedrock console.
* **Qdrant and JupyterHub now declare `depends_on` for the `gp3` StorageClass.**
  Both charts create a PVC that needs it, but nothing ordered them after the
  StorageClass in `addons.tf`. On a first apply Helm installed them while `gp3`
  did not yet exist, the PVCs stayed Pending, and both releases failed after ten
  minutes with `Error: context deadline exceeded`. The workloads then came up on
  their own once the StorageClass appeared, so the failure was spurious, but the
  apply exited non-zero. If you hit this on an older copy of the code, just run
  `terraform apply` again.
* The JupyterHub values file is fetched over HTTP from the book's S3 bucket. Its
  notebook profiles reference `jupyter/pyspark-notebook` images from the retired
  Docker Hub `jupyter/*` organization; they still pull, but new images are
  published under `quay.io/jupyter/*`.

## Clean up

```bash
kubectl delete -f chatbot/chatbot-deploy.yaml      # removes the ELB
kubectl delete -f rag-app/rag-deploy.yaml
kubectl delete -f inference/finetuned-inf-deploy.yaml
kubectl delete job my-llama-job qdrant-restore-job
terraform destroy
```

The S3 bucket in `model-assets.tf` has no `force_destroy`, so empty it first:
`aws s3 rm s3://$(terraform output -raw my_llama_bucket) --recursive`.

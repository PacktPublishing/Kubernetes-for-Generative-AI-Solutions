
<b><p align='center'>[![Packt Sale](https://static.packt-cdn.com/assets/images/humble+bundle/cloud_infrastructure_and_devops_toolkit_packt_books_Social.png)](https://www.humblebundle.com/books/cloud-infrastructure-and-devops-toolkit-packt-books?hmb_source=&hmb_medium=product_tile&hmb_campaign=mosaic_section_1_layout_index_1_layout_type_threes_tile_index_1_c_cloudinfrastructureanddevopstoolkitpackt_bookbundle)</p></b> 

# Kubernetes for Generative AI Solutions

<a href="https://www.packtpub.com/en-us/product/kubernetes-for-generative-ai-solutions-9781836209935"><img src="https://content.packt.com/_/image/original/B31108/cover_image.jpg?version=1749204926" alt="Book Name" height="256px" align="right"></a>

This is the code repository for [Kubernetes for Generative AI Solutions](https://www.packtpub.com/en-us/product/kubernetes-for-generative-ai-solutions-9781836209935), published by Packt.

**A complete guide to designing, optimizing, and deploying Generative AI workloads on Kubernetes**

## What is this book about?
Learn step by step how to design, optimize, and deploy Generative AI projects on Kubernetes. Covering networking, observability, security, scaling, and cost optimization strategies, this guide takes you from first deployment to production excellence.

This book covers the following exciting features:
* Explore GenAI deployment stack, agents, RAG, and model fine-tuning
* Implement HPA, VPA, and Karpenter for efficient autoscaling
* Optimize GPU usage with fractional allocation, MIG, and MPS setups
* Reduce cloud costs and monitor spending with Kubecost tools
* Secure GenAI workloads with RBAC, encryption, and service meshes
* Monitor system health and performance using Prometheus and Grafana
* Ensure high availability and disaster recovery for GenAI systems
* Automate GenAI pipelines for continuous integration and delivery

If you feel this book is for you, get your [copy](https://www.amazon.com/Kubernetes-Generative-Solutions-designing-optimizing/dp/1836209932) today!

<a href="https://www.packtpub.com/?utm_source=github&utm_medium=banner&utm_campaign=GitHubBanner"><img src="https://raw.githubusercontent.com/PacktPublishing/GitHub/master/GitHub.png" 
alt="https://www.packtpub.com/" border="5" /></a>


## Instructions and Navigations
All of the code is organized into folders. For example, ch2.

The code will look like the following:
```
...
  metadata {
    name = "gp2"
...
```

### Getting the code

Clone the repository and export `REPO` so it points at your clone. Every chapter
README uses `$REPO` in its commands, so set this once per shell:

```bash
git clone https://github.com/PacktPublishing/Kubernetes-for-Generative-AI-Solutions.git
cd Kubernetes-for-Generative-AI-Solutions
export REPO=$(pwd)
```

Check it before you start, and re-run the `export` in any new terminal:

```bash
echo "$REPO"        # should print the path to your clone
ls "$REPO/ch3"      # should list addons.tf, eks.tf, vpc.tf, ...
```

To make it stick across shells, add the export to your `~/.bashrc` or `~/.zshrc`.

### Chapter guide

Every chapter folder has its own `README.md` with the prerequisites, the exact
commands to run, how to verify the result, and how to tear it down. Start there:

| Chapter | Title | Code in this repo |
|---------|-------|-------------------|
| 1 | GenAI: Intro, Evolution, and Project Lifecycle | none |
| 2 | K8s: Introduction and Integration with GenAI | [ch2](ch2): Flask and llama-cpp-python container |
| 3 | Getting Started with K8s in the Cloud | [ch3](ch3): baseline EKS cluster, VPC, add-ons, ECR |
| 4 | GenAI Model Optimization for Domain-Specific Use Cases (RAG, Fine Tuning, etc.) | [ch4](ch4): notebooks for fine-tuning, RAG, agents |
| 5 | Getting Started with GenAI on K8s: Chatbot Example | [ch5](ch5): GPU nodes, JupyterHub, Qdrant, RAG and chatbot apps |
| 6 | Deploying GenAI on K8s: Scaling Best Practices | [ch6](ch6): HPA, VPA, Karpenter |
| 7 | Deploying GenAI on K8s: Cost Optimization Best Practices | [ch7](ch7): Kubecost |
| 8 | Deploying GenAI on K8s: Networking Best Practices | [ch8](ch8): network policies |
| 9 | Deploying GenAI on K8s: Security Best Practices | [ch9](ch9): Bottlerocket, Pod Identity, Secrets Store CSI, ECR scanning |
| 10 | Optimizing GPU Resources in K8s for GenAI Applications | [ch10](ch10): time-slicing, MIG, MPS |
| 11 | GenAIOps: Creating GenAI Automation Pipeline | [ch11](ch11): KubeRay, Ray Serve, vLLM |
| 12 | Getting Visibility into GenAI Workloads Resource Utilization | [ch12](ch12): Prometheus, Grafana, DCGM |
| 13 | High Availability and Disaster Recovery Implementation | none |
| 14 | Wrap Up and Further Readings | [ch14](ch14): Amazon Q demo, TODO app |

Chapters 1 and 13 ship no code in this repository, so there are no `ch1` or
`ch13` folders. The chapter titles above use a colon where the book's titles use
a dash.

### How the Terraform chapters fit together

The Terraform in this repository is **incremental**, not standalone. `ch3` builds
the baseline cluster; later chapters ship only the files they add or change, and
you copy them over the baseline in a single working directory. Files with the
same name replace the earlier version.

```bash
# 1. Create one working directory and lay down the ch3 baseline
mkdir -p ~/eks-genai && cd ~/eks-genai
cp $REPO/ch3/*.tf .

# 2. Overlay the chapter you are working through (ch5 shown here)
cp $REPO/ch5/*.tf .

# 3. Apply
terraform init && terraform apply
```

Each chapter README states exactly which layers to stack. Keep using the same
directory (and the same Terraform state) as you move through the book, so each
chapter builds on the last instead of creating a second cluster.

Working straight through, the sequence is:

```bash
cd ~/eks-genai
cp $REPO/ch3/*.tf .                          # baseline
terraform init && terraform apply
cp $REPO/ch5/*.tf .  && terraform apply      # GPU nodes, JupyterHub, Qdrant
cp $REPO/ch6/*.tf .  && rm -f karpenter.tf && terraform apply
cp $REPO/ch7/*.tf .  && terraform apply      # Kubecost
cp $REPO/ch9/*.tf .  && terraform apply      # security
cp $REPO/ch10/*.tf . && terraform apply      # GPU time-slicing
cp $REPO/ch11/*.tf . && terraform apply      # KubeRay
cp $REPO/ch12/*.tf . && cp $REPO/ch12/kube-prometheus.yaml . && terraform apply
```

Two things to know about stacking this way:

* **`ch6/karpenter.tf` is reference only.** Every chapter's `addons.tf` already
  declares Karpenter, so copying `karpenter.tf` as well produces a duplicate that
  breaks Chapters 7, 9 and 12. The `rm -f` above is deliberate.
* **Later chapters keep earlier resources.** Each `addons.tf` carries forward the
  EBS CSI driver and the `gp3` StorageClass, so overlaying a chapter does not
  delete the volumes Qdrant and JupyterHub are using.

From Chapter 6 onward there is no static GPU managed node group: `eks.tf` comments
it out, and GPU capacity comes from the Karpenter `NodePool` in
`ch6/eks-gpu-np.yaml` instead. Apply that NodePool before Chapters 10 and 11,
which both need GPUs.

`versions.tf`, `providers.tf`, `locals.tf`, and `vpc.tf` live only in `ch3` and
are reused unchanged by every later chapter. Cluster name, region, VPC CIDR, and
AZs come from `ch3/locals.tf`. The Kubernetes version is set in the `eks` module
block of whichever chapter's `eks.tf` you are using:

```hcl
cluster_version = "1.36"
```

`eks.tf` ships in ch3, ch5, ch6, and ch9, so if you change the version, change it
in the one you copied last.

### Version matrix

The code has been updated and verified against the versions below. Every chapter
was checked with `terraform init`/`validate`/`plan`, all manifests were validated
against the Kubernetes 1.36 and CRD schemas, and the container images were built
and smoke-tested.

| Component | Version | Notes |
|-----------|---------|-------|
| Terraform CLI | >= 1.11 | verified on 1.16.2 |
| AWS provider | >= 5.96 | resolves to 5.100.x; EKS module v20 supplies the `< 6.0.0` cap |
| Kubernetes provider | >= 2.36, < 3.0 | cap added by hand, see note below |
| Helm provider | >= 2.17 | resolves to 2.17.0; the add-on modules supply the `< 3.0` cap |
| Amazon EKS / Kubernetes | 1.36 | set in `eks.tf` (ch3, ch5, ch6, ch9) |
| `terraform-aws-modules/eks` | ~> 20.37 | |
| `terraform-aws-modules/vpc` | ~> 5.21 | |
| `terraform-aws-modules/iam` | ~> 5.60 | pinned: v6 removed the `iam-role-for-service-accounts-eks` submodule |
| `aws-ia/eks-blueprints-addons` | ~> 1.23.0 | 1.23 is the last release that supports the Helm 2.x provider |
| `aws-ia/eks-data-addons` | ~> 1.38.0 | |
| Karpenter | 1.14.1 | chart >= 1.13 is required for Kubernetes 1.36 |
| NVIDIA device plugin | 0.20.0 | |
| JupyterHub (z2jh) | 4.4.2 | |
| kube-prometheus-stack | 90.2.0 | |
| prometheus-adapter | 5.3.0 | |
| Secrets Store CSI driver | 1.6.1 | |
| AWS provider for Secrets Store CSI | 3.1.3 | |
| DCGM exporter | 4.8.3 | |
| KubeRay operator | 1.7.0 | |
| Qdrant | 1.19.1 | |
| Kubecost | 3.2.4 | chart renamed from `cost-analyzer` to `kubecost` |
| Vertical Pod Autoscaler | 5.0.1 | ch6 only |

#### Why this stack stays on AWS 5.x and Helm 2.x

The AWS and Helm provider constraints in `versions.tf` are still the book's
original `>= 5.96` and `>= 2.17`, and they do not need upper bounds, because the
modules already impose them:

* `terraform-aws-modules/eks` v20 declares `aws < 6.0.0`.
* `aws-ia/eks-blueprints-addons` v1.23 declares `helm < 3.0`, and it requires
  `helm >= 3.0` from v1.24 onward, which is why the module pin is `~> 1.23.0`.
* `aws-ia/eks-data-addons` (JupyterHub and the NVIDIA device plugin in ch5, ch10,
  ch11, and ch12) declares `aws ~> 5.95` and `helm ~> 2.17`.

Terraform intersects all of these, so `>= 5.96` resolves to 5.100.x and
`>= 2.17` resolves to 2.17.0 on its own.

The one constraint that had to be added by hand is the Kubernetes provider's
`< 3.0`. Nothing in the module graph caps it, so `>= 2.36` alone selects the 3.x
provider, which deprecates `kubernetes_namespace` and the other resources these
chapters use. The configuration still plans on 3.x, but with deprecation warnings.

Moving to the AWS 6.x and Helm 3.x providers would mean moving to EKS module v21,
which renames `cluster_name` to `name` and `cluster_version` to
`kubernetes_version`, and replacing `eks-data-addons` with plain `helm_release`
resources. That is a much larger change, and it would make the code stop matching
the snippets printed in the book.

Note also that the module version constraints use a three-part form in places.
`~> 1.23.0` allows 1.23.x but not 1.24.0, whereas `~> 1.23` would allow 1.24.x
and break the Helm 2.x cap.

### Python dependency pins

`requirements.txt` files and the `pip install` lines in the notebooks and
Dockerfiles are pinned on purpose, not merely snapshotted:

* **LangChain is held on the 0.3 line.** `ch5/rag-app/main.py` and the ch4
  notebooks use `langchain.memory`, `langchain.text_splitter`,
  `langchain.chat_models`, `langchain.document_loaders`, and
  `RetrievalQA`. LangChain 1.x moved or removed all of these.
* **transformers is held on the 4.x line** (and `datasets` on 3.x) because the
  fine-tuning and inference scripts target that `Trainer`/`TrainingArguments` API.
* **Gradio is held on the 5.x line** because `ch5/chatbot/gradio-app.py` builds
  chat history as `(user, bot)` tuples, which Gradio 6 removed.
* **Base images are pinned to `python:3.13-slim`.** The unqualified `python:slim`
  tag now resolves to Python 3.14, where the pinned LangChain/pydantic stack
  fails to evaluate forward-referenced type annotations.

**Following is what you need for this book:**
This book is for solutions architects, product managers, engineering leads, DevOps teams, GenAI developers, and AI engineers. It's also suitable for students and academics learning about GenAI, Kubernetes, and cloud-native technologies. A basic understanding of cloud computing and AI concepts is needed, but no prior knowledge of Kubernetes is required.

With the following software and hardware list you can run all code files present in the book (Chapter 1-14).

### Software and Hardware List

| Chapter | Software/Hardware Required        | OS Required                                           |
|---------|-----------------------------------|--------------------------------------------------------|
| 1–14    | Operating system                  | Linux, macOS, Windows (via WSL)                        |
| 1–14    | Kubernetes                        | Amazon EKS, kind (for local testing)                   |
| 1–14    | AI/ML frameworks                  | Hugging Face Transformers, PyTorch, TensorFlow         |
| 1–14    | Accelerators                      | NVIDIA GPUs, AWS Trainium/Inferentia                   |
| 1–14    | Observability                     | Prometheus, Grafana, OpenTelemetry, Loki               |
| 1–14    | Automation                        | Kubeflow, MLflow, Ray, Argo Workflows                  |
| 1–14    | Security tools                    | OPA, Kyverno                                           |

### Command-line tools

| Tool | Minimum | Purpose |
|------|---------|---------|
| AWS CLI | v2 | authentication, `aws eks update-kubeconfig` |
| Terraform | >= 1.11 | provisioning every cluster in the book |
| kubectl | within one minor of 1.36 | interacting with the cluster |
| Helm | 3.x | inspecting and installing charts |
| Docker | any recent | building the sample application images |
| Python | 3.9+ with `pip` (3.10+ preferred) | Hugging Face CLI, the Chapter 4 notebooks, the sample apps |
| curl | any recent | calling the deployed APIs in the verification steps |
| jq | any recent | reading the JSON those APIs return |

Before you start, confirm your credentials and pick a region that has the GPU
capacity the later chapters need:

```bash
aws sts get-caller-identity
aws eks describe-cluster-versions --region us-west-2 \
  --query 'clusterVersions[].{version:clusterVersion,status:status,default:defaultVersion}' --output table
```

> **Cost warning.** These chapters create real infrastructure: an EKS control
> plane, NAT gateways, EBS volumes, load balancers, and GPU instances (`g6`)
> that are billed per hour. Run `terraform destroy` when you finish a chapter,
> and delete any `LoadBalancer` Services first so their ELBs are removed before
> the VPC.

### Related products
* Platform Engineering for Architects [[Packt]](https://www.packtpub.com/en-us/product/platform-engineering-for-architects-9781836203599) [[Amazon]](https://www.amazon.com/Platform-Engineering-Architects-Crafting-platforms/dp/1836203594/)

* Kubernetes – An Enterprise Guide – Third Edition [[Packt]](https://www.packtpub.com/en-us/product/kubernetes-an-enterprise-guide-9781835086957) [[Amazon]](https://www.amazon.com/Kubernetes-Enterprise-Effectively-containerize-applications/dp/1835086950/)

## Get to Know the Authors
**Sukirti Gupta** is a technologist and product management leader at Amazon Web Services (AWS),
where he leads the adoption of Generative AI technologies across start-up ecosystems. With over 15
years of experience in cloud computing, AI/ML, and data center technologies, he has played influential
roles in shaping product narratives and engineering solutions for high-impact workloads across AWS,
AMD, and Intel.
At AWS, Sukirti leads initiatives that help start-ups integrate GenAI into their product strategy, enabling
them to innovate with powerful infrastructure and tools. His previous roles include leading cloud
product development at AMD and managing GTM strategy for Intel’s flagship computing platforms,
where he helped drive billion-dollar revenue programs.
Sukirti holds a B.Tech. from IIT (BHU), Varanasi, an M.S. in electrical engineering from the University
of Cincinnati, and an MBA in strategy and marketing from Santa Clara University.
In addition to his corporate work, Sukirti loves to mentor AI start-ups through IIT’s accelerator
programs and frequently writes on Medium about GenAI trends and product leadership.

**Ashok Srirama** is a principal specialist solutions architect at AWS, where he leads initiatives to
architect scalable, secure, and cost-efficient container-based solutions for enterprise customers. With
over 19 years of experience in IT, Ashok brings profound expertise in cloud architecture, Kubernetes,
container platforms, and, most recently, Generative AI.
Before joining AWS, Ashok held pivotal cloud architecture roles at AIG and IBM, where he led digital
transformation initiatives and cloud migration projects across insurance and communication sectors.
His technical acumen spans across designing distributed architectures, infrastructure automation,
and application modernization using containers and serverless technologies.
As a recognized thought leader in cloud-native architecture, Ashok has authored numerous technical
publications, including 20+ official AWS blogs and technical guides on Amazon EKS networking,
observability, security, and container CI/CD pipelines. He has presented at over 25+ public events,
including AWS re:Invent, AWS Summits, and start-up CTO cohorts, sharing his expertise with the
broader technical community.
Ashok’s commitment to technical excellence is reflected in his extensive certification portfolio, which
encompasses all 12 AWS technical certifications and the complete suite of Kubernetes certifications
from the Linux Foundation. His achievements have earned him the coveted AWS Gold Jacket and
Kubestronaut accreditation.
Beyond his architectural work, Ashok is passionate about enabling developers to simplify the complexity
of running GenAI workloads at scale using cloud-native tools.

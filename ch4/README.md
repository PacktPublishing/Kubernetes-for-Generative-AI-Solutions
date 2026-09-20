# Chapter 4. GenAI Model Optimization for Domain-Specific Use Cases (RAG, Fine Tuning, etc.)

Three notebooks covering the GenAI techniques the rest of the book deploys on
Kubernetes. Nothing here needs a cluster; they were written for Google Colab and
run just as well in JupyterHub (Chapter 5 installs one on the cluster) or any
local Jupyter.

## Notebooks

| Notebook | What it covers |
|----------|----------------|
| `GenAIModelOptimization_FineTuning_Example.ipynb` | QLoRA fine-tuning of Llama with 4-bit quantization, PEFT, and W&B tracking |
| `GenAIModelOptimization_RAG_Example.ipynb` | Retrieval-augmented generation over a CSV using an in-memory vector store |
| `GenAIModelOptimization_LangChain_Agents.ipynb` | A LangChain agent driving the Python REPL tool |

## Prerequisites

| Notebook | Needs |
|----------|-------|
| Fine-tuning | A GPU runtime (Colab T4 or better), a Hugging Face token with access to the gated `meta-llama` repos, and a W&B API key |
| RAG | An OpenAI API key |
| LangChain agents | An OpenAI API key |

The fine-tuning and RAG notebooks mount Google Drive (`from google.colab import
drive`). Outside Colab, delete those cells and point the file paths at local
files instead.

Set credentials as environment variables rather than pasting them into cells:

```python
import os, getpass
os.environ["OPENAI_API_KEY"] = getpass.getpass("OpenAI key: ")
```

## Running them

Open in Colab, choose a GPU runtime for the fine-tuning notebook, and run the
cells top to bottom. Each notebook installs its own dependencies in the first
cell.

## Version notes

The `!pip install` cells are pinned, which matters here more than usual:

```
langchain==0.3.30  langchain-core==0.3.86  langchain-community==0.3.31
langchain-experimental==0.3.4  langchain-openai==0.2.14
transformers==4.57.6  peft==0.20.0  datasets==3.6.0
accelerate==1.15.0  bitsandbytes==0.50.2
```

These notebooks use LangChain's original import paths:
`langchain.chat_models`, `langchain.document_loaders`, `langchain.vectorstores`,
and `langchain.llms`. Those still resolve on the 0.3 line (with deprecation
warnings) but were **removed in LangChain 1.x**, so an unpinned
`pip install langchain` breaks the notebooks at the first import.

If you would rather modernize than pin, the replacements are:

| Notebook import | Current equivalent |
|-----------------|--------------------|
| `from langchain.chat_models import ChatOpenAI` | `from langchain_openai import ChatOpenAI` |
| `from langchain.llms import OpenAI` | `from langchain_openai import OpenAI` |
| `from langchain.document_loaders import CSVLoader` | `from langchain_community.document_loaders import CSVLoader` |
| `from langchain.vectorstores import DocArrayInMemorySearch` | `from langchain_community.vectorstores import DocArrayInMemorySearch` |

Similarly, `transformers` is held at 4.x: version 5 changed the
`Trainer`/`TrainingArguments` API the fine-tuning notebook relies on.

## Next

Chapter 5 takes these same techniques (fine-tuning, RAG, and a chat UI) and
runs them as containers on the cluster.

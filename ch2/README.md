# Chapter 2. K8s: Introduction and Integration with GenAI

A minimal Flask API that loads a quantized Llama 2 model with
[`llama-cpp-python`](https://github.com/abetlen/llama-cpp-python) and serves it
on port 5000. This is the "hello world" of the book: it runs entirely on CPU, so
you can build and test it on a laptop before touching Kubernetes.

## Files

| File | Purpose |
|------|---------|
| `app.py` | Flask app exposing `POST /predict` |
| `Dockerfile` | Builds the image on `python:3.12` |

## Prerequisites

* Docker.
* Python 3.9 or newer with `pip`. This is needed only on your own machine, to
  install the Hugging Face CLI for the model download; the app itself uses the
  Python inside the container.
* `curl` and `jq`, for the test request further down.
* A GGUF model file. The code expects `llama-2-7b-chat.Q2_K.gguf` in the build
  context. That is the smallest quantization, roughly 2.8 GB.

Check the tooling before you start:

```bash
docker --version
python3 --version          # 3.9 or newer
```

Download the model from Hugging Face. This repository is public, so no token and
no licence acceptance are needed:

```bash
python3 -m pip install --upgrade huggingface_hub
hf download TheBloke/Llama-2-7B-Chat-GGUF llama-2-7b-chat.Q2_K.gguf --local-dir .
```

`hf` is the current Hugging Face CLI. The older `huggingface-cli` name is
deprecated and does nothing in huggingface_hub 1.x, and its
`--local-dir-use-symlinks` flag has been removed.

Any GGUF chat model works. If you use a different file, update the filename in
`app.py`.

## Build and run

```bash
docker build -t my-llama .
docker run --rm -p 5000:5000 my-llama
```

The first build takes several minutes (about six on a small instance):
`llama-cpp-python` compiles native code. That is also why the `Dockerfile` uses
the full `python:3.12` image rather than `-slim`, because the slim variant has no
C/C++ toolchain.

`COPY . /app` bakes the model file into the image, so with the 7B model the image
is about 4.1 GB. To keep it small while you iterate, move the `.gguf` out of the
build context and mount it at run time instead:

```bash
docker run --rm -p 5000:5000 \
  -v "$PWD/llama-2-7b-chat.Q2_K.gguf:/app/llama-2-7b-chat.Q2_K.gguf:ro" my-llama
```

## Test it

```bash
curl -s -X POST http://localhost:5000/predict \
  -H 'Content-Type: application/json' \
  -d '{"sys_msg":"You are a helpful assistant.","prompt":"What is Kubernetes?"}' | jq .
```

You get back the raw `llama-cpp` completion object, with the generated text at
`.response.choices[0].text`.

## Version notes

* The base image is pinned to `python:3.12` and `llama-cpp-python` to `0.3.35`.
  The original `FROM python` resolved to whatever `latest` happened to be, which
  made builds non-reproducible.
* CPU inference is slow. A full-length answer from the 7B Q2_K model took about
  150 seconds on a small instance. Chapter 5 moves inference onto GPU nodes.
* `app.py` asks for `max_tokens=1000`, but llama-cpp-python defaults its context
  window to `n_ctx=512`, so replies stop at 512 total tokens and report
  `finish_reason: "length"`, even though this model was trained with 4096. Raise
  it if you want longer answers:
  `llama_cpp.Llama("llama-2-7b-chat.Q2_K.gguf", n_ctx=4096)`.
* Q2_K is the most aggressive quantization, chosen here for size. Expect
  noticeably degraded output, including the occasional stray word mid-sentence.
  `Q4_K_M` from the same repository is a better trade if you have the disk.
* `app.py` runs Flask's development server, which handles one request at a time.
  A second request waits for the first generation to finish, so do not read a
  slow concurrent response as a hang.

## Next

Chapter 3 builds the EKS cluster that this image gets deployed to, and creates
the ECR repository (`my-llama`) to push it into.

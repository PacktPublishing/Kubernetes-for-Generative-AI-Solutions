FROM nvidia/cuda:12.8.1-runtime-ubuntu24.04

# Environment config
ENV DEBIAN_FRONTEND=noninteractive
ENV VIRTUAL_ENV=/opt/venv
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# Install Python and necessary dependencies
RUN apt-get update && apt-get install -y python3.12 python3.12-venv python3-pip && rm -rf /var/lib/apt/lists/*

# Set Python3 as default
RUN python3.12 -m venv $VIRTUAL_ENV && $VIRTUAL_ENV/bin/pip install --upgrade pip

# Install necessary packages. transformers is held on the 4.x line and
# datasets on 3.x because fine_tune.py targets those APIs.
RUN pip install --no-cache-dir \
      torch==2.14.0 \
      transformers==4.57.6 \
      datasets==3.6.0 \
      peft==0.20.0 \
      accelerate==1.15.0 \
      bitsandbytes==0.50.2 \
      sentencepiece==0.2.2 \
      s3fs==2025.12.0 \
      boto3==1.43.93

WORKDIR /app

# Copy script
COPY fine_tune.py /app/fine_tune.py

# Run the fine-tuning script
CMD ["python", "fine_tune.py"]

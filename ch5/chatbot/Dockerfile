# Use an official Python runtime as a parent image
# Pinned: the unqualified `python:slim` tag now resolves to Python 3.14,
# where the pinned LangChain 0.3 / pydantic stack fails to evaluate
# forward-referenced type annotations.
FROM python:3.13-slim

# Set the working directory to /app
WORKDIR /app

# Copy the current directory contents into the container at /app
COPY requirements.txt /app

# Install any needed packages specified in requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Expose the port Gradio runs on
EXPOSE 7860

COPY gradio-app.py /app

ENTRYPOINT ["python", "gradio-app.py"]

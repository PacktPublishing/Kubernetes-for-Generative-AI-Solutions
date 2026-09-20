# Use an official Python runtime as a parent image.
# The full (non-slim) image is deliberate: llama-cpp-python compiles
# native code at install time and needs a C/C++ toolchain.
FROM python:3.12

# Set the working directory 
WORKDIR /app 

# Expose the application on port 5000 
EXPOSE 5000 

# Define environment variable 
ENV FLASK_APP=app.py 

# Install any needed packages specified in requirements.txt 
RUN pip install --no-cache-dir flask==3.1.3 llama-cpp-python==0.3.35

# Copy the current dir contents into the container at /app 
COPY . /app 

# Run app.py when the container launches 
CMD ["python", "app.py"] 
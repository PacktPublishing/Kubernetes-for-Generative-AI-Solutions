# Kubernetes Deployment for TODO Application

This directory contains Kubernetes manifests to deploy the TODO application in an EKS cluster.

## Manifest Files

- `namespace.yaml`: Creates a dedicated namespace for the application
- `deployment.yaml`: Deploys two replicas of the TODO application
- `service.yaml`: Exposes the application via a ClusterIP service
- `configmap.yaml`: Contains configuration for the application
- `kustomization.yaml`: Kustomize configuration for deploying all resources

## Deployment Steps

### 1. Build and Push the Docker Image to ECR

First, you need to build and push your Docker image to Amazon ECR:

```bash
# Login to ECR
aws ecr get-login-password --region <your-region> | docker login --username AWS --password-stdin <your-account-id>.dkr.ecr.<your-region>.amazonaws.com

# Create ECR repository (if it doesn't exist)
aws ecr create-repository --repository-name todo-app --region <your-region>

# Tag the image
docker tag todo-app:latest <your-account-id>.dkr.ecr.<your-region>.amazonaws.com/todo-app:latest

# Push the image
docker push <your-account-id>.dkr.ecr.<your-region>.amazonaws.com/todo-app:latest
```

### 2. Update the Deployment Image

Update the image in the deployment.yaml file to point to your ECR repository:

```yaml
image: <your-account-id>.dkr.ecr.<your-region>.amazonaws.com/todo-app:latest
```

### 3. Deploy to EKS

```bash
# Create the namespace
kubectl apply -f namespace.yaml

# Deploy all resources using kustomize
kubectl apply -k .
```

### 4. Verify the Deployment

```bash
# Check if pods are running
kubectl get pods -n todo-app

# Check the service
kubectl get svc -n todo-app
```

### 5. Access the Application

Since we're using a ClusterIP service, the application is only accessible within the cluster. To access it externally, you can:

1. Use port forwarding:
   ```bash
   kubectl port-forward -n todo-app svc/todo-app 8080:80
   ```
   Then access the application at http://localhost:8080

2. Or create an Ingress resource (not included) to expose it through an ALB/NLB.

## Configuration

The application uses the following environment variables that can be configured in the ConfigMap:

- `PORT`: The port the application listens on (default: 5000)

## Notes

- `deployment.yaml` ships with `image: todo-app:latest` and
  `imagePullPolicy: IfNotPresent`, which works for a local `kind` cluster where
  you can side-load the image (`kind load docker-image todo-app:latest`). For EKS
  you must push to a registry and set the full image reference, as described in
  step 2 above.
- The liveness and readiness probes both hit `/`, which renders the UI template.
  If you change the routes, update the probe paths to match.
- `kubectl apply -k .` already creates the namespace, since `namespace.yaml` is
  listed in `kustomization.yaml` - the separate `kubectl apply -f namespace.yaml`
  in step 3 is belt-and-braces, not a requirement.

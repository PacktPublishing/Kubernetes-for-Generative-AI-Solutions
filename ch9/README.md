# Chapter 9. Deploying GenAI on K8s: Security Best Practices

Replaces the plaintext Hugging Face token from Chapter 5 with AWS Secrets Manager
and EKS Pod Identity, switches the nodes to Bottlerocket, and turns on enhanced
ECR image scanning.

## Layers

`$REPO` points at your clone of this repository; see
[Getting the code](../README.md#getting-the-code) if you have not set it.

```bash
cd ~/eks-genai
cp $REPO/ch3/*.tf .    # baseline
cp $REPO/ch5/*.tf .    # GPU nodes, JupyterHub, Qdrant
cp $REPO/ch9/*.tf .    # this chapter
terraform init && terraform apply
```

`ch9/eks.tf`, `ch9/addons.tf`, and `ch9/ecr.tf` replace the ch5 versions;
`iam.tf` is new.

> Switching the node group's `ami_type` to Bottlerocket **replaces the nodes**.
> Expect the existing managed nodes to be rolled and workloads rescheduled.

## Files

| File | Purpose |
|------|---------|
| `eks.tf` | Node group moved to `BOTTLEROCKET_x86_64`, 3 nodes |
| `addons.tf` | Adds the Secrets Store CSI driver and its AWS provider |
| `iam.tf` | IAM role, Secrets Manager read policy, and the Pod Identity association for `my-llama-sa` |
| `ecr.tf` | Marks `my-llama-finetuned` immutable and enables enhanced continuous scanning |
| `inference/secret-provider-class.yaml` | `SecretProviderClass` mounting `hugging-face-secret` and syncing it to a Kubernetes Secret |
| `inference/finetuned-inf-deploy.yaml` | The inference deployment, reading the token from the synced Secret |

## Prerequisites

Create the secret in Secrets Manager first. The IAM policy in `iam.tf` scopes to
the name `hugging-face-secret`:

```bash
aws secretsmanager create-secret \
  --name hugging-face-secret \
  --secret-string 'hf_xxxxxxxxxxxxxxxxxxxxx' \
  --region us-west-2
```

You also need the `my-llama-sa` service account, which the deployment references:

```bash
kubectl create serviceaccount my-llama-sa
```

## Deploy

```bash
terraform apply

kubectl get nodes -o wide                          # Bottlerocket OS image
kubectl get pods -n kube-system -l app=secrets-store-csi-driver
kubectl get pods -n kube-system -l app=csi-secrets-store-provider-aws
```

Then the workload:

```bash
cd inference
kubectl apply -f secret-provider-class.yaml
# set your ECR image in finetuned-inf-deploy.yaml first
kubectl apply -f finetuned-inf-deploy.yaml
```

## Verify

The token should arrive without ever appearing in a manifest:

```bash
# Mounted as a file by the CSI driver
kubectl exec deploy/my-llama-finetuned-deployment -- \
  ls -l /mnt/secrets-store/

# Synced into a Kubernetes Secret (syncSecret.enabled = true)
kubectl get secret hugging-face-secret \
  -o jsonpath='{.data.token}' | base64 -d | head -c 8; echo '...'

# And injected as an env var from that Secret
kubectl exec deploy/my-llama-finetuned-deployment -- \
  sh -c 'echo ${HUGGING_FACE_HUB_TOKEN} | head -c 8'
```

Confirm Pod Identity is what grants the access:

```bash
aws eks list-pod-identity-associations --cluster-name eks-demo --region us-west-2
kubectl describe pod -l app.kubernetes.io/name=my-llama-finetuned | grep -i -A3 'aws-sm-secrets'
```

Check the image scan findings:

```bash
aws ecr describe-image-scan-findings \
  --repository-name my-llama-finetuned --image-id imageTag=latest --region us-west-2
```

## How the pieces connect

1. `iam.tf` creates a role trusted by `pods.eks.amazonaws.com` (the Pod Identity
   principal, not an OIDC/IRSA trust) with `secretsmanager:GetSecretValue` scoped
   to `hugging-face-secret*`.
2. `aws_eks_pod_identity_association` binds that role to
   `default:my-llama-sa`.
3. `secret-provider-class.yaml` sets `usePodIdentity: "true"`, so the AWS provider
   uses the association rather than IRSA.
4. `secretObjects` mirrors the mounted secret into a Kubernetes Secret, which the
   deployment consumes via `secretKeyRef`.

The volume mount is what triggers the fetch. A `SecretProviderClass` alone does
nothing, and the synced Kubernetes Secret only exists while at least one pod
mounts it.

## Version notes

* Secrets Store CSI driver 1.6.1 (was 1.5.0) and the AWS provider 3.1.3 (was
  1.0.1). `usePodIdentity` is supported throughout that range.
* Kubecost is carried over from Chapter 7 in this `addons.tf`, with the chart
  rename and values-URL fix described in the [ch7 README](../ch7/README.md).
* `ecr.tf` sets `image_tag_mutability = "IMMUTABLE"` on `my-llama-finetuned`, so
  pushing the same tag twice fails by design. Use unique tags.
* **`iam.tf` hardcodes two names that are not derived from the cluster:**
  `my-llama-app-role` and `hf-secrets-access-policy`. Renaming the cluster in
  `locals.tf` (the Chapter 3 collision workaround) does **not** avoid these, so if
  a previous run left them behind the apply fails with `EntityAlreadyExists`.
  Check first, and edit `iam.tf` if they exist:

  ```bash
  aws iam get-role --role-name my-llama-app-role
  aws iam list-policies --scope Local \
    --query "Policies[?PolicyName=='hf-secrets-access-policy'].Arn" --output text
  ```

* **`aws_ecr_registry_scanning_configuration` is Region-wide, not per-repository.**
  It rewrites the scanning configuration for the entire registry in that Region,
  and enhanced scanning is billed per image. Note what you have before applying,
  because a later `terraform destroy` resets it. A registry that started on
  `ENHANCED` comes back as `BASIC`, which silently downgrades scanning for every
  repository in the Region. Record the setting first and put it back afterwards:

  ```bash
  aws ecr get-registry-scanning-configuration --region us-west-2
  ```
* Bottlerocket has no shell or package manager. Debug with
  `kubectl debug node/<node> -it --image=public.ecr.aws/amazonlinux/amazonlinux`.

## Clean up

```bash
kubectl delete -f inference/finetuned-inf-deploy.yaml -f inference/secret-provider-class.yaml
terraform destroy
aws secretsmanager delete-secret --secret-id hugging-face-secret \
  --force-delete-without-recovery --region us-west-2
```

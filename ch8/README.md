# Chapter 8. Deploying GenAI on K8s: Networking Best Practices

Two `NetworkPolicy` manifests that lock down the Chapter 5 inference and RAG
services so only the chat UI can reach them. There is no Terraform here; these
apply to the cluster you already have.

## Files

| File | Purpose |
|------|---------|
| `rag-app-ingress-policy.yaml` | Allows ingress to `rag-app` on TCP/80 only from `chatbot-ui` pods |
| `fine-tuned-llama-ingress-policy.yaml` | Same for `my-llama-finetuned` |

Both select by the `app.kubernetes.io/name` label and set
`policyTypes: [Ingress]`, so egress is untouched.

## Prerequisites

* A cluster from Chapter 3 (plus Chapter 5's workloads to actually test against).
* **A CNI that enforces NetworkPolicy.** This is the part that catches people
  out: the Amazon VPC CNI only enforces network policies when the feature is
  explicitly enabled. Without it the policies are accepted by the API server and
  silently do nothing.

### Enable enforcement in the VPC CNI

Network policy support is off by default. Turn it on in the add-on
configuration. In `addons.tf`, change:

```hcl
vpc-cni = {}
```

to:

```hcl
vpc-cni = {
  configuration_values = jsonencode({
    enableNetworkPolicy = "true"
  })
}
```

Then `terraform apply`. Verify:

```bash
kubectl get ds -n kube-system aws-node \
  -o jsonpath='{.spec.template.spec.containers[*].name}{"\n"}'
# expect: aws-node aws-eks-nodeagent

kubectl get ds -n kube-system aws-node \
  -o jsonpath='{range .spec.template.spec.containers[*]}{.name}: {.args}{"\n"}{end}' \
  | grep -i network-policy
```

`enable-network-policy=true` should appear on the node agent.

## Apply

```bash
kubectl apply -f rag-app-ingress-policy.yaml
kubectl apply -f fine-tuned-llama-ingress-policy.yaml
kubectl get networkpolicies
```

## Verify enforcement

The point is that an *allowed* client works and a *disallowed* one does not.

Allowed, from the chat UI pod:

```bash
kubectl exec -it deploy/chatbot-ui-deployment -- \
  python -c "import requests; print(requests.post('http://rag-app-service.default:80/generate', json={'prompt':'hi'}).status_code)"
```

Denied, from a pod without the `chatbot-ui` label:

```bash
kubectl run netcheck --rm -it --image=curlimages/curl:8.18.0 --restart=Never -- \
  curl -sS --max-time 5 http://rag-app-service.default:80/generate
```

That second command should time out. If it returns a response, enforcement is not
active. Recheck the VPC CNI setting above.

Try it both ways to be sure the policy is doing the work: before applying it,
both clients get a response. After applying it, only the labelled client
succeeds and the other times out. Allow roughly 20 seconds after
`kubectl apply` for the node agent to program the rules, and confirm enforcement
is really on with:

```bash
kubectl get ds -n kube-system aws-node \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="aws-eks-nodeagent")].args}' \
  | tr ',' '\n' | grep network-policy
```

It must read `--enable-network-policy=true`. It is `false` by default, which is
why the policies otherwise appear to do nothing.

## Notes

* **Default-deny is the useful pattern.** These two policies only cover two
  workloads. Anything without a policy stays fully open. Add a namespace-wide
  default-deny and then allow specific paths:

  ```yaml
  apiVersion: networking.k8s.io/v1
  kind: NetworkPolicy
  metadata:
    name: default-deny-ingress
  spec:
    podSelector: {}
    policyTypes: [Ingress]
  ```

* **Port 80 is the Service port and the container port** for both workloads, so
  the policies match either way. If you change `targetPort`, note that
  `NetworkPolicy` matches the *pod* port, not the Service port.
* **Don't lock out kube-system.** DNS lives there; these ingress-only policies
  leave egress to CoreDNS alone, but a default-deny *egress* policy would break
  name resolution unless you allow UDP/TCP 53 to kube-system.

## Version notes

Both manifests use `networking.k8s.io/v1`, which is stable and unchanged. They
were already valid and needed no updates. The only thing that has changed since
the book is the emphasis on enabling enforcement in the VPC CNI, which is
required for any of this to have an effect.

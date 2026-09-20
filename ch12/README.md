# Chapter 12. Getting Visibility into GenAI Workloads Resource Utilization

Deploys kube-prometheus-stack (Prometheus, Grafana, and the operator), wires up
DCGM GPU metrics, Ray Serve metrics, and Qdrant metrics, and adds alerting rules
for GPU health and inference latency.

## Layers

`$REPO` points at your clone of this repository; see
[Getting the code](../README.md#getting-the-code) if you have not set it.

```bash
cd ~/eks-genai
cp $REPO/ch3/*.tf .    # baseline
cp $REPO/ch5/*.tf .    # GPU nodes, JupyterHub, Qdrant
cp $REPO/ch12/*.tf .   # this chapter
cp $REPO/ch12/kube-prometheus.yaml .   # values file read by addons.tf
terraform init && terraform apply
```

`ch12/addons.tf` and `ch12/aiml-addons.tf` replace the ch5 versions.

> Copy `kube-prometheus.yaml` too. `addons.tf` reads it with
> `templatefile("${path.module}/kube-prometheus.yaml", ...)`, so Terraform fails
> if it is not in the working directory.

## Files

| File | Purpose |
|------|---------|
| `addons.tf` | kube-prometheus-stack, prometheus-adapter, Secrets Store CSI, Kubecost |
| `aiml-addons.tf` | Device plugin, JupyterHub, KubeRay operator, and DCGM exporter with `serviceMonitor` enabled |
| `kube-prometheus.yaml` | Helm values: 5h retention, 15s scrape, 50 GiB gp3 volume, Grafana on, Alertmanager off |
| `monitoring/gpu-rules.yaml` | `PrometheusRule`: GPU memory, utilization, temperature, ECC, and XID alerts |
| `monitoring/ray-serve-rules.yaml` | `PrometheusRule`: Ray Serve latency, error rate, throughput |
| `monitoring/ray-svc-monitor.yaml` | `ServiceMonitor` for the Ray head (metrics, autoscaler, dashboard) |
| `monitoring/ray-worker-monitor.yaml` | `PodMonitor` for Ray workers |
| `monitoring/qdrant-monitor.yaml` | `ServiceMonitor` for Qdrant |
| `dashboards/ray-serve-dashboard.json` | Grafana dashboard for Ray Serve |

## Deploy

```bash
terraform apply
kubectl get pods -n monitoring
kubectl get pods -n dcgm-exporter
```

Then the monitors and rules:

```bash
kubectl apply -f monitoring/
kubectl get servicemonitors,podmonitors,prometheusrules -n monitoring
```

## Access Prometheus and Grafana

```bash
# Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Grafana
kubectl get secret -n monitoring kube-prometheus-stack-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d; echo
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
```

Grafana is at <http://localhost:3000> (user `admin`). Import the Ray dashboard via
**Dashboards → New → Import → Upload JSON** and select
`dashboards/ray-serve-dashboard.json`.

> Service names follow the Helm release name. Confirm with
> `kubectl get svc -n monitoring` if the port-forwards above don't resolve.

## Verify the metrics are flowing

The important check is that Prometheus has actually discovered the targets, not
just that the pods are up. In the Prometheus UI go to **Status → Targets**, or:

```bash
# GPU metrics from DCGM
# dcgm-exporter only schedules where a GPU node exists: its nodeAffinity needs
# nvidia.com/gpu.count, which GPU Feature Discovery adds. With no GPU node the
# DaemonSet sits at DESIRED 0, which is expected, not broken.
curl -s 'localhost:9090/api/v1/query?query=DCGM_FI_DEV_GPU_UTIL' | jq '.data.result | length'

# Ray Serve metrics (needs Chapter 11 running)
curl -s 'localhost:9090/api/v1/query?query=ray_serve_num_http_requests_total' | jq '.data.result | length'

# Qdrant
curl -s 'localhost:9090/api/v1/query?query=up{job="qdrant"}' | jq '.data.result'

# Loaded alert rules
curl -s localhost:9090/api/v1/rules | jq -r '.data.groups[].name'
```

Give the operator a couple of minutes first. Immediately after
`kubectl apply -f monitoring/` the new rules and targets are genuinely absent.
`nvidia-gpu.rules`, `ray-serve.rules` and the qdrant targets typically take about
two minutes to show up. Do not start debugging selectors until you have waited.

A `length` of `0` after that means the `ServiceMonitor` isn't matching. Two things make that
happen here, and both are already handled in this chapter's config:

* `serviceMonitorSelectorNilUsesHelmValues: false` in `kube-prometheus.yaml`, so
  Prometheus picks up monitors that don't carry the Helm release label.
* `release: kube-prometheus-stack` labels on every monitor and rule in
  `monitoring/`.

## What the alerts cover

`gpu-rules.yaml` fires on:

| Alert | Condition |
|-------|-----------|
| `GPUMemoryUsageHigh` | framebuffer > 90% for 5m |
| `GPUHighUtilization` | utilization > 90% for 5m |
| `GPULowUtilization` | utilization < 20% for 5m, the cost signal |
| `GPUTemperatureHigh` | > 80 °C for 5m |
| `GPUECCErrorsDetected` | any correctable ECC error in 10m |
| `GPUXidCriticalError` | any XID error in 10m, usually real hardware trouble |

`ray-serve-rules.yaml` covers p95 latency > 1s, error rate > 5%, throughput
under 1 rps, average latency > 500 ms, and missing Ray node metrics.

Alertmanager is disabled in the values file, so these alerts show up in the
Prometheus UI but are not routed anywhere. Set `alertmanager.enabled: true` and
add a receiver to send them on.

## Version notes

* **kube-prometheus-stack 90.2.0** (was 72.3.0) and **prometheus-adapter 5.3.0**
  (was 4.46.0). Both are large jumps; the values used here
  (`prometheusSpec.retention`, `storageSpec`, `grafana.defaultDashboardsEnabled`,
  `serviceMonitorSelectorNilUsesHelmValues`) are unchanged across them.
* **DCGM exporter pinned to 4.8.3** and **KubeRay operator to 1.7.0**, instead of
  tracking whatever the chart repositories currently serve.
* Secrets Store CSI driver 1.6.1 and its AWS provider 3.1.3, carried over from
  Chapter 9.
* Kubecost's chart rename and moved values file are fixed here as well. See the
  [ch7 README](../ch7/README.md) for details.
* The NVIDIA device plugin config, including the Chapter 10 time-slicing
  settings, is carried forward here. Dropping it would silently turn GPU sharing
  back off on an upgrade.
* Note the `nvidia.com/gpu.count` node-affinity selector on DCGM exporter in this
  chapter's `aiml-addons.tf`; Chapters 10 and 11 use `nvidia.com/gpu.present`.
  Both labels come from GPU Feature Discovery.
* `prometheus-adapter` is installed to serve custom metrics through the
  `custom.metrics.k8s.io` API, which is what lets an HPA scale on something like
  queue depth rather than CPU. Configuring those rules is left as an exercise.

## Clean up

```bash
kubectl delete -f monitoring/
terraform destroy
```

The Prometheus PVC is not removed by `helm uninstall`. Check for leftovers with
`kubectl get pvc -n monitoring` and delete them so the EBS volumes go away.

# ACT 3 — Monitoring: ServiceMonitor & Prometheus

> **Script:** `scripts/07-monitoring.sh`
> **Overview:** OpenShift ships with a full monitoring stack (Prometheus + Alertmanager + Thanos) pre-installed. User workloads are registered for scraping via a `ServiceMonitor` custom resource.

---

## Mental Model

To scrape a **user workload**, a `ServiceMonitor` CR tells Prometheus where and how to pull metrics from a Service:

```
App → exposes /q/metrics (Prometheus text format)
ServiceMonitor → tells Prometheus: "scrape that Service every 15s"
Prometheus → stores the time-series data
Console → Observe → Metrics / Targets / Dashboards
```

> **Key point:** No Prometheus configuration files to edit. No YAML to merge into a cluster config. One CR — and the app is scraped.

---

## Steps

### 1. Live Metrics Endpoint

The Quarkus app exposes Micrometer metrics at `/q/metrics` out of the box — no instrumentation code required:

```bash
curl http://<route>/q/metrics | head -20
```

Included automatically:
- **JVM metrics** — heap, GC, threads
- **HTTP metrics** — request count, error rate, latency histograms
- **System metrics** — CPU usage, file descriptors

---

### 2. Enable User-Workload Monitoring (cluster-admin, once per cluster)

```yaml
# ConfigMap: openshift-monitoring / cluster-monitoring-config
data:
  config.yaml: |
    enableUserWorkload: true
```

> **Note:** Without this flag, Prometheus only scrapes cluster infrastructure components. User workloads are opt-in at the cluster level — this is a deliberate security boundary.

---

### 3. ServiceMonitor

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: ocp-demo-app
  labels:
    app: ocp-demo-app
spec:
  selector:
    matchLabels:
      app: ocp-demo-app      # must match the Service label
  endpoints:
    - port: 8080-tcp
      path: /q/metrics
      interval: 15s
```

```bash
oc apply -f servicemonitor.yaml -n ocp-demo
oc get servicemonitor -n ocp-demo
```

Within ~30 seconds, the app endpoint appears under **Observe → Targets** with status `UP`.

---

### 4. Querying Metrics in the Console

**Observe → Metrics**

Example PromQL queries:

```promql
# HTTP request rate (all endpoints)
http_server_requests_seconds_count{namespace="ocp-demo"}

# JVM heap used
jvm_memory_used_bytes{namespace="ocp-demo", area="heap"}

# CPU usage
process_cpu_usage{namespace="ocp-demo"}
```

**Console:** Observe → Dashboards → **Kubernetes / Compute Resources / Namespace (Pods)**
→ CPU, memory, and network per pod — with request and limit overlays.

---

## Recap

| What | How | Result |
|---|---|---|
| App metrics | Micrometer at `/q/metrics` | JVM + HTTP + system metrics — zero code |
| Cluster flag | `enableUserWorkload: true` | Prometheus eligible to scrape user workloads |
| `ServiceMonitor` | One CR pointing at the Service | App scraped every 15 s |
| Console | Observe → Targets / Metrics | Live PromQL + pre-built dashboards |

---

## Key Commands

```bash
# Verify ServiceMonitor
oc get servicemonitor -n ocp-demo

# Sample metrics output
curl http://<route>/q/metrics | head -20

# Check scrape targets (via console or oc)
oc get servicemonitor ocp-demo-app -n ocp-demo -o yaml
```

---

## ⬅️ Previous: [Resource Requests & Limits](08-resources.md) | ➡️ Next: [Scaling Out](10-scaling.md)

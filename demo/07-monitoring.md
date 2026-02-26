# ACT 3 — Monitoring, Health Probes & Resource Limits

> **Script:** `scripts/07-monitoring.sh`
> **Goal:** Configure Prometheus scraping for the workload, wire liveness/readiness probes, and set resource requests/limits — all three are required for a production-grade deployment.

---

## Mental Model

Three distinct concerns, each independently configurable:

| Concern | Mechanism | Failure action |
|---|---|---|
| Observability | `ServiceMonitor` → Prometheus scrape | Metrics appear in Observe → Metrics |
| Health management | Liveness / Readiness probes | Pod restarted or removed from load balancer |
| Resource isolation | Requests / Limits | Throttle (CPU) or OOMKill + restart (memory) |

> **Take away:** These are not optional production hardening steps. They are the baseline contract between a workload and the platform.

---

## PART 1 — ServiceMonitor: Prometheus Scraping

### Concept

The OpenShift monitoring stack (Prometheus + Alertmanager + Thanos) is already running. To scrape a user workload, register a `ServiceMonitor` — a CR that tells Prometheus where to pull metrics.

The Quarkus app exposes Micrometer metrics at `/q/metrics` (Prometheus format) out of the box.

### Steps

**1. Verify the live metrics endpoint:**

```bash
curl http://<route>/q/metrics | head -20
```

> **Tip:** JVM metrics, HTTP latency histograms, and GC stats are included automatically via Micrometer. No instrumentation code required.

---

**2. Enable user-workload monitoring (cluster-admin, once per cluster):**

```yaml
# ConfigMap: openshift-monitoring / cluster-monitoring-config
data:
  config.yaml: |
    enableUserWorkload: true
```

> **Gotcha:** Without this flag, Prometheus only scrapes cluster components. User workloads are opt-in at the cluster level.

---

**3. Apply the ServiceMonitor:**

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
      app: ocp-demo-app
  endpoints:
    - port: 8080-tcp
      path: /q/metrics
      interval: 15s
```

> **Goal:** Within ~30 seconds, the app endpoint appears under **Observe → Targets** as `UP`.

**PromQL verification:**

```promql
http_server_requests_seconds_count{namespace="ocp-demo"}
```

---

## PART 2 — Liveness & Readiness Probes

### Concept

| Probe | Endpoint | Failure action |
|---|---|---|
| **Readiness** | `/q/health/ready` | Pod removed from Service — no traffic received |
| **Liveness** | `/q/health/live` | Container killed and restarted by kubelet |

Both are implemented in the app via MicroProfile Health:

```java
@Liveness  @ApplicationScoped
public static class AppLiveness implements HealthCheck { ... }  // /q/health/live

@Readiness @ApplicationScoped
public static class AppReadiness implements HealthCheck { ... } // /q/health/ready
```

### Steps

**1. Verify the endpoints:**

```bash
curl http://<route>/q/health/live
curl http://<route>/q/health/ready
```

Expected:
```json
{ "status": "UP", "checks": [{ "name": "app-live", "status": "UP" }] }
```

---

**2. Patch probes onto the Deployment:**

```yaml
livenessProbe:
  httpGet:
    path: /q/health/live
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 10
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /q/health/ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
  failureThreshold: 3
```

> **Gotcha:** `initialDelaySeconds` must account for JVM startup time. If probes fire before the JVM is ready, the pod enters a restart loop before the application has a chance to initialise.

---

**3. Example — failing liveness event (from `oc describe pod`):**

```
Warning  Unhealthy  Liveness probe failed: HTTP probe failed with statuscode: 503
Warning  Killing    Container failed liveness probe, will be restarted
Normal   Pulled     Successfully pulled image ...
Normal   Started    Started container
```

> **Take away:** The platform detects and recovers from a stuck container automatically. No alerting pipeline, no manual restart required.

---

## PART 3 — Resource Requests & Limits

### Concept

```
requests  ──→  guaranteed minimum  (scheduler uses this for node placement)
limits    ──→  hard ceiling        (throttle CPU / OOMKill for memory)
```

| Without limits | With limits |
|---|---|
| Noisy-neighbour workload can starve the node | Hard cap enforced per container |
| Scheduler makes uninformed placement decisions | Scheduler has accurate resource accounting |
| OOM kills affect random pods on the node | OOMKill is scoped to the offending container |
| No visibility into consumption vs. allocation | Graphs show actual vs. request vs. limit |

### QoS Classes

| Configuration | QoS class | Eviction priority |
|---|---|---|
| `requests == limits` (both set) | **Guaranteed** | Last to be evicted |
| `requests < limits` | **Burstable** | Medium |
| Neither set | **BestEffort** | First to be evicted |

### Steps

**1. Inspect current (empty) resources:**

```bash
oc get deployment ocp-demo-app \
  -o jsonpath='{.spec.template.spec.containers[0].resources}'
```

---

**2. Patch requests + limits:**

```yaml
resources:
  requests:
    cpu: "100m"      # 0.1 core — guaranteed at scheduling time
    memory: "256Mi"  # 256 MiB reserved on the node
  limits:
    cpu: "500m"      # 0.5 core — CPU throttled above this
    memory: "512Mi"  # 512 MiB — OOMKilled above this
```

> **Tip:** `100m` = 100 millicores = 0.1 CPU core. A container that attempts to use more than `500m` is throttled; one that exceeds `512Mi` memory is killed and restarted.

---

**3. Verify with `oc adm top`:**

```bash
oc adm top pod -n ocp-demo -l app=ocp-demo-app
```

**Console:** Observe → Dashboards → **Kubernetes / Compute Resources / Namespace (Pods)**
→ Each pod bar shows actual consumption vs. request vs. limit.

---

**4. Namespace-level guardrails:**

```bash
oc get limitrange -n ocp-demo
oc get resourcequota -n ocp-demo
```

> **Take away:** `LimitRange` sets per-container defaults and maxima. `ResourceQuota` caps total consumption per namespace. Cluster admins use both to prevent any single team from exhausting node resources.

---

## Recap

| What was configured | Why it matters |
|---|---|
| `ServiceMonitor` | Prometheus scrapes `/q/metrics` → visible in Observe → Targets |
| Readiness probe | Pod is removed from the load balancer when not ready — zero failed requests |
| Liveness probe | kubelet auto-restarts stuck containers — no manual intervention |
| `resources.requests` | Scheduler places pods on appropriately sized nodes |
| `resources.limits` | Noisy containers are throttled or restarted — other pods are unaffected |

---

## Key Commands

```bash
# Verify ServiceMonitor
oc get servicemonitor -n ocp-demo

# Inspect probe configuration
oc get deployment ocp-demo-app \
  -o jsonpath='{.spec.template.spec.containers[0].livenessProbe}'

# Live resource consumption
oc adm top pod -n ocp-demo

# Namespace quota and limits
oc get resourcequota,limitrange -n ocp-demo
```

---

## ➡️ Next: [Scaling Out](08-scaling.md)

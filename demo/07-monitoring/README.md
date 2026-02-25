# ACT 3 — Monitoring, Health Probes & Resource Limits

> **Duration:** ~10 minutes  
> **Script:** `scripts/07-monitoring.sh`  
> **Wow Factor:** Production-grade observability + self-protection — zero YAML written from scratch  
> **Message:** *"Observability, health management και resource isolation δεν είναι add-ons. Είναι μέρος του platform."*

---

## 🎯 Mental Model First

> 💬 *"Τρία πράγματα που ένα production σύστημα πρέπει να έχει από την πρώτη μέρα: να μετράει τον εαυτό του, να ξέρει αν είναι υγιές, και να μην 'τρώει' όλους τους πόρους του node."*

---

## 🖥️ PART 1 — ServiceMonitor: scraping our app with Prometheus

### Concept

The OpenShift monitoring stack (Prometheus + Alertmanager + Thanos) is **already running**. To scrape a workload, we register a `ServiceMonitor` — a custom resource that tells Prometheus *where* to pull metrics.

Our Quarkus app exposes Micrometer metrics at `/q/metrics` (Prometheus format) out of the box.

### Steps

**1. Show the live metrics endpoint:**

```bash
curl http://<route>/q/metrics | head -20
```

> 💬 *"Αυτά τα metrics βγαίνουν αυτόματα από το Quarkus/Micrometer. JVM, HTTP latency, GC — όλα μέσα."*

---

**2. Enable user-workload monitoring (cluster-admin — once per cluster):**

```yaml
# ConfigMap: openshift-monitoring / cluster-monitoring-config
data:
  config.yaml: |
    enableUserWorkload: true
```

> 💬 *"Αυτό λέει στο Prometheus: 'κοίτα και τα workloads των namespaces, όχι μόνο τα cluster components'."*

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

> 💬 *"Ένα μικρό YAML και ο Prometheus ξέρει να scrape-άρει την εφαρμογή μας κάθε 15 δευτερόλεπτα."*

**Console:** Navigate to **Observe → Targets** — the app endpoint will appear within ~30 s.

**PromQL demo query:**
```promql
http_server_requests_seconds_count{namespace="ocp-demo"}
```

---

## 🖥️ PART 2 — Liveness & Readiness Probes

### Concept

| Probe | Endpoint | Failure action |
|-------|----------|---------------|
| **Readiness** | `/q/health/ready` | Pod removed from Service — **no traffic received** |
| **Liveness** | `/q/health/live` | Container **killed and restarted** by kubelet |

Our Quarkus app implements both via MicroProfile Health:

```java
@Liveness  @ApplicationScoped
public static class AppLiveness implements HealthCheck { ... }  // /q/health/live

@Readiness @ApplicationScoped
public static class AppReadiness implements HealthCheck { ... } // /q/health/ready
```

### Steps

**1. Hit the endpoints live:**

```bash
curl http://<route>/q/health/live
curl http://<route>/q/health/ready
```

Expected response:
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

> 💬 *"initialDelaySeconds δίνει χρόνο στο JVM να ξεκινήσει πριν αρχίσουν οι ελέγχοι. Αν αποτύχει 3 φορές το liveness — restart. Αν αποτύχει το readiness — βγαίνει από το load-balancer."*

---

**3. What a failing liveness event looks like (`oc describe pod`):**

```
Warning  Unhealthy  Liveness probe failed: HTTP probe failed with statuscode: 503
Warning  Killing    Container failed liveness probe, will be restarted
Normal   Pulled     Successfully pulled image ...
Normal   Started    Started container
```

> 💬 *"Αυτό είναι self-healing σε επίπεδο container — χωρίς να χρειαστεί κανείς να κάνει τίποτα."*

**Console:** Workloads → Deployments → `ocp-demo-app` → YAML → search `livenessProbe`

---

## 🖥️ PART 3 — Resource Requests & Limits

### Concept

```
requests  ──→  guaranteed minimum  (scheduler uses this for placement)
limits    ──→  hard ceiling        (throttle CPU / OOMKill for memory)
```

| Without limits | With limits |
|----------------|-------------|
| Noisy-neighbour can starve node | Hard cap per container |
| Scheduler guesses placement | Scheduler makes optimal decisions |
| OOM kills random pods | OOMKill only the offending container |
| No visibility into consumption | Graphs show request vs actual |

### QoS Classes

| requests == limits | QoS class | Priority |
|--------------------|-----------|----------|
| ✅ Both set equal | **Guaranteed** | Highest — last to be evicted |
| Requests < limits | **Burstable** | Medium |
| Neither set | **BestEffort** | Lowest — first to be evicted |

### Steps

**1. Show current (empty) resources:**

```bash
oc get deployment ocp-demo-app -o jsonpath='{.spec.template.spec.containers[0].resources}'
```

---

**2. Patch requests + limits:**

```yaml
resources:
  requests:
    cpu: "100m"      # 0.1 core guaranteed at scheduling
    memory: "256Mi"  # 256 MiB reserved on the node
  limits:
    cpu: "500m"      # 0.5 core max — throttled above this
    memory: "512Mi"  # 512 MiB max — OOMKilled above this
```

> 💬 *"100m CPU = 1/10 ενός core. Αν η εφαρμογή προσπαθήσει να χρησιμοποιήσει πάνω από 500m — throttle. Αν χρησιμοποιήσει πάνω από 512Mi RAM — OOMKill και restart."*

---

**3. Verify with `oc adm top`:**

```bash
oc adm top pod -n ocp-demo -l app=ocp-demo-app
```

**Console:** Observe → Dashboards → **Kubernetes / Compute Resources / Namespace (Pods)**  
→ Each pod bar shows actual vs requested vs limit.

---

**4. Show LimitRange / ResourceQuota (cluster admin guardrails):**

```bash
oc get limitrange -n ocp-demo
oc get resourcequota -n ocp-demo
```

> 💬 *"Ο cluster admin μπορεί να ορίσει LimitRange — defaults και maxima ανά container — και ResourceQuota — συνολικό budget ανά namespace. Έτσι κανένας developer δεν μπορεί να 'φάει' τον cluster."*

---

## 📌 Recap

| What we did | Why it matters |
|-------------|---------------|
| `ServiceMonitor` | Prometheus scrapes `/q/metrics` → metrics in Observe → Targets |
| Readiness probe (`/q/health/ready`) | Pod exits load-balancer when not ready — zero failed requests |
| Liveness probe (`/q/health/live`) | Kubelet auto-restarts stuck containers |
| `resources.requests` | Scheduler places pods optimally |
| `resources.limits` | Noisy containers are throttled / restarted, not neighbours |

---

## 🔑 Key Commands

```bash
# View ServiceMonitor
oc get servicemonitor -n ocp-demo

# Check probe config
oc get deployment ocp-demo-app -o jsonpath='{.spec.template.spec.containers[0].livenessProbe}'

# Live resource usage
oc adm top pod -n ocp-demo

# Namespace quota
oc get resourcequota,limitrange -n ocp-demo
```

---

## ➡️ Next: [Scaling Out](../08-scaling/README.md)

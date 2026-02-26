# ACT 3 — Resource Requests & Limits

> **Script:** `scripts/08-resources.sh`
> **Overview:** Resource requests and limits govern scheduling, CPU throttling, and memory-based eviction in OpenShift.

---

## Mental Model

Two independent knobs per container:

```
requests  ──→  guaranteed minimum  (scheduler uses this for node placement)
limits    ──→  hard ceiling        (CPU: throttle / RAM: OOMKill + restart)
```

| Without limits | With limits |
|---|---|
| One noisy pod can exhaust all node CPU/RAM | Hard cap enforced per container |
| Scheduler makes uninformed placement decisions | Scheduler has accurate resource accounting |
| OOM kills affect random pods on the node | OOMKill is scoped to the offending container |
| No visibility into consumption vs. allocation | Console shows actual / request / limit bars |

### QoS Classes

| Configuration | QoS class | Eviction priority under node pressure |
|---|---|---|
| `requests == limits` (both set) | **Guaranteed** | Last to be evicted |
| `requests < limits` | **Burstable** | Medium |
| Neither set | **BestEffort** | First to be evicted |

---

## Steps

### 1. BestEffort State (No Resources Configured)

```bash
oc get deployment ocp-demo-app \
  -o jsonpath='{.spec.template.spec.containers[0].resources}'
# → {} or empty — BestEffort: first evicted under pressure
```

> **Note:** An empty `resources` block does not mean "no limits apply". It means the container competes for whatever is left — and can be evicted without warning.

---

### 2. Configuring Requests and Limits

```yaml
resources:
  requests:
    cpu: "100m"      # 0.1 core — guaranteed at scheduling time
    memory: "256Mi"  # 256 MiB reserved on the node
  limits:
    cpu: "500m"      # 0.5 core — CPU throttled above this
    memory: "512Mi"  # 512 MiB — OOMKilled above this
```

```bash
oc patch deployment ocp-demo-app -n ocp-demo \
  --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources","value":{
    "requests":{"cpu":"100m","memory":"256Mi"},
    "limits":{"cpu":"500m","memory":"512Mi"}
  }}]'
```

> **Tip:** `100m` = 100 millicores = 0.1 CPU. A container that attempts more than `500m` is throttled (slowed, not killed). One that exceeds `512Mi` RAM is OOMKilled and restarted.

---

### 3. CPU Throttle Behaviour

With a tight CPU limit (`cpu: 100m`) and the CPU burn endpoint active:

```bash
# Tighten the limit
oc set resources deployment/ocp-demo-app \
  --requests=cpu=100m,memory=256Mi \
  --limits=cpu=100m,memory=512Mi -n ocp-demo

# Trigger all-core CPU burn
curl http://<route>/api/burn?seconds=20
```

While the burn runs:

```bash
watch oc adm top pod -n ocp-demo -l app=ocp-demo-app
# CPU column stays CAPPED at 100m — throttled, not killed
```

> **Key point:** CPU throttling is transparent to the application. The container slows but keeps running. Unlike memory — where exceeding the limit terminates the container immediately.

Restore after the demonstration:

```bash
oc set resources deployment/ocp-demo-app \
  --requests=cpu=100m,memory=256Mi \
  --limits=cpu=500m,memory=512Mi -n ocp-demo
```

---

### 4. Live Resource Consumption

```bash
oc adm top pod -n ocp-demo -l app=ocp-demo-app
# NAME                        CPU(cores)   MEMORY(bytes)
# ocp-demo-app-xxx-yyy        12m          198Mi
```

**Console:** Observe → Dashboards → **Kubernetes / Compute Resources / Namespace (Pods)**
→ Each pod row shows: actual consumption / request bar / limit bar.

---

### 5. Namespace-Level Guardrails

```bash
# LimitRange — per-container defaults and maxima (set by cluster admin)
oc get limitrange -n ocp-demo

# ResourceQuota — total budget for the namespace
oc get resourcequota -n ocp-demo
```

> **Key point:** `LimitRange` injects default requests/limits when developers omit them, preventing BestEffort pods from reaching production. `ResourceQuota` caps the entire team's namespace budget.

---

## Recap

| What | How | Why |
|---|---|---|
| `requests` | Scheduling guarantee | Kubernetes places pods on nodes that can honour the request |
| `limits.cpu` | Throttle | Container slows — stays alive |
| `limits.memory` | OOMKill + restart | Keeps the node stable; scoped to the offending container |
| LimitRange | Namespace default | Prevents BestEffort pods in production |
| ResourceQuota | Namespace cap | Prevents one team from exhausting cluster capacity |

---

## Key Commands

```bash
# Inspect current resource config
oc get deployment ocp-demo-app \
  -o jsonpath='{.spec.template.spec.containers[0].resources}'

# Live resource consumption
oc adm top pod -n ocp-demo

# Namespace quota and limits
oc get resourcequota,limitrange -n ocp-demo
```

---

## ➡️ Next: [Health Probes](08-probes.md)

# ACT 3 — Scaling Out

> **Script:** `scripts/08-scaling.sh`
> **Goal:** Demonstrate manual horizontal scaling and Horizontal Pod Autoscaler (HPA) reacting to real CPU load.

---

## Mental Model

Two distinct scaling modes:

```
Manual Scaling  → operator decides when and how many replicas
Auto Scaling    → platform decides based on observed metrics (HPA)
```

> **Tip:** Manual scaling is appropriate for anticipated load events (planned release, scheduled batch). HPA is appropriate for unpredictable or variable workloads.

---

## Steps

### 1. Manual scale UP to 3 replicas

```bash
oc scale deployment/ocp-demo-app --replicas=3 -n ocp-demo
```

Observe in Topology: 3 pods appear, all with dark blue ring (healthy).

The script sends **6 requests** and prints the `hostname` field from each response — demonstrating load distribution across all 3 pods.

> **Take away:** Round-robin load balancing across all healthy replicas is automatic. No additional configuration required.

---

### 2. Scale back DOWN to 1 replica

```bash
oc scale deployment/ocp-demo-app --replicas=1 -n ocp-demo
```

---

### 3. Configure a Horizontal Pod Autoscaler (HPA)

```bash
oc autoscale deployment/ocp-demo-app \
  --min=1 --max=5 --cpu-percent=50 \
  -n ocp-demo
```

```bash
oc get hpa ocp-demo-app -n ocp-demo
# NAME           TARGETS    MINPODS   MAXPODS   REPLICAS
# ocp-demo-app   <unknown>  1         5         1
```

> **Gotcha:** `TARGETS: <unknown>` is expected immediately after HPA creation. The controller requires one metrics scrape interval to populate the current CPU value. It will resolve within ~30 seconds.

> **Take away:** When average CPU across all running pods exceeds 50%, the HPA scales up — to a maximum of 5 replicas. When load drops, it scales back down to the minimum.

---

### 4. Trigger real CPU load — observe HPA response

The script launches **10 parallel clients**, each calling `/api/burn?seconds=90` in a loop for 120 seconds:

```bash
# 10 background workers — each loops until 120s elapsed
for c in $(seq 1 10); do
  ( while true; do curl /api/burn?seconds=90 ...; sleep 1; done ) &
done
```

Live pod status is printed every 5 seconds:

```
[t+0s]   ocp-demo-app-xxx(Running)
[t+30s]  ocp-demo-app-xxx(Running) ocp-demo-app-yyy(Running) ocp-demo-app-zzz(Running)
[t+60s]  ... 4 pods running
```

> **Goal:** Observe the HPA controller increasing the replica count in response to measured CPU pressure — without any manual intervention.

---

### 5. Cleanup — HPA removed, reset to 3 replicas

```bash
oc delete hpa ocp-demo-app -n ocp-demo --ignore-not-found
oc scale deployment/ocp-demo-app --replicas=3 -n ocp-demo
```

The deployment is reset to 3 replicas as the starting state for the self-healing demo.

---

## Recap

| Method | When to use | Command |
|---|---|---|
| Manual scale | Known load event (planned) | `oc scale --replicas=N` |
| HPA | Variable or unpredictable load | `oc autoscale` |
| Scale to zero | Cost reduction in non-production environments | `oc scale --replicas=0` |

> **Tip:** Scale-to-zero is valid for development and staging namespaces — workloads consume no compute resources when replicas = 0. Restore with a single `oc scale` command.

---

## ➡️ Next: [Self-Healing Pods](09-self-healing.md)

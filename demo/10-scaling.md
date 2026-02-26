# ACT 3 — Scaling Out

> **Script:** `scripts/10-scaling.sh`
> **Overview:** OpenShift supports both manual horizontal scaling and automatic scaling via the Horizontal Pod Autoscaler (HPA), which reacts to real CPU load.

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

### 1. Manual Scale UP to 3 Replicas

```bash
oc scale deployment/ocp-demo-app --replicas=3 -n ocp-demo
```

In Topology, 3 pods appear — all with a dark blue ring (healthy).

Sending 6 requests and inspecting the `hostname` field in each response demonstrates round-robin load distribution across all 3 pods.

> **Key point:** Round-robin load balancing across all healthy replicas is automatic. No additional configuration required.

---

### 2. Scale Back Down to 1 Replica

```bash
oc scale deployment/ocp-demo-app --replicas=1 -n ocp-demo
```

---

### 3. Horizontal Pod Autoscaler (HPA)

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

> **Note:** `TARGETS: <unknown>` is expected immediately after HPA creation. The controller requires one metrics scrape interval to populate the current CPU value — this resolves within ~30 seconds.

> **Key point:** When average CPU across all running pods exceeds 50%, the HPA scales up — to a maximum of 5 replicas. When load drops, it scales back down to the configured minimum.

---

### 4. HPA Response to Real CPU Load

The script launches **10 parallel clients**, each calling `/api/burn?seconds=90` in a loop for 120 seconds:

```bash
# 10 background workers — each loops until 120s elapsed
for c in $(seq 1 10); do
  ( while true; do curl /api/burn?seconds=90 ...; sleep 1; done ) &
done
```

Pod status is polled every 5 seconds:

```
[t+0s]   ocp-demo-app-xxx(Running)
[t+30s]  ocp-demo-app-xxx(Running) ocp-demo-app-yyy(Running) ocp-demo-app-zzz(Running)
[t+60s]  ... 4 pods running
```

The HPA controller increases the replica count in response to measured CPU pressure — without any manual intervention.

---

### 5. Cleanup

```bash
oc delete hpa ocp-demo-app -n ocp-demo --ignore-not-found
oc scale deployment/ocp-demo-app --replicas=3 -n ocp-demo
```

The deployment is reset to 3 replicas as the starting state for the self-healing demonstration.

---

## Recap

| Method | When to use | Command |
|---|---|---|
| Manual scale | Known load event (planned) | `oc scale --replicas=N` |
| HPA | Variable or unpredictable load | `oc autoscale` |
| Scale to zero | Cost reduction in non-production environments | `oc scale --replicas=0` |

> **Tip:** Scale-to-zero is valid for development and staging namespaces — workloads consume no compute resources when replicas = 0. Restore with a single `oc scale` command.

---

## ⬅️ Previous: [Monitoring — ServiceMonitor](09-monitoring.md) | ➡️ Next: [Self-Healing Pods](11-self-healing.md)

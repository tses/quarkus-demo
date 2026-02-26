# ACT 3 — Self-Healing Pods

> **Script:** `scripts/11-self-healing.sh`
> **Overview:** OpenShift runs a continuous reconciliation loop — when a pod is removed, the platform detects the divergence and schedules a replacement automatically, with no manual intervention.

---

## Mental Model

OpenShift runs a continuous **reconciliation loop**:

```
Desired state:  3 pods running
Actual state:   2 pods running (one terminated)
Action:         Immediately schedule a replacement pod
```

> **Key point:** The platform does not wait for an alert, an on-call response, or a manual restart. It acts on the divergence between desired and actual state within seconds.

---

## Steps

### 1. Starting State — 3 Pods Running

This step begins from the state left by the scaling demonstration (3 replicas).

```bash
oc get pods -l app=ocp-demo-app -n ocp-demo
```

All 3 pods show `Running` status and dark blue rings in **Topology**.

---

### 2. Split View Setup

A useful observation layout:

- **Left:** Topology view (visual — watch pod count change)
- **Right:** Terminal running the script

> **Tip:** The visual contrast between a missing pod ring and its replacement appearing is the clearest way to observe the reconciliation cycle.

---

### 3. Pod Deletion

The script highlights the target pod before deletion:

```
╔══════════════════════════════════════╗
║   KILLING POD: ocp-demo-app-xxx...   ║
╚══════════════════════════════════════╝
```

```bash
oc delete pod <pod-name> -n ocp-demo
```

The pod disappears from the Topology view. Within seconds, a replacement pod starts its initialisation cycle.

---

### 4. Recovery — Live Polling

The script polls every 2 seconds for 30 seconds:

```
[t+2s]  Running pods: 2/3
[t+4s]  Running pods: 2/3
[t+6s]  Running pods: 3/3  ✅
```

> **Key point:** Total recovery time is typically under 10 seconds for a pre-pulled image. No human action is required at any point.

---

### 5. The Replacement Pod

```bash
oc get pods -l app=ocp-demo-app -n ocp-demo
# NAME                        STATUS    RESTARTS   AGE
# ocp-demo-app-xxx-abc12      Running   0          14m
# ocp-demo-app-xxx-def34      Running   0          14m
# ocp-demo-app-xxx-xyz99      Running   0          9s   ← NEW
```

> **Note:** The new pod has a different name — it is a genuinely new container, not a restart of the original. The `AGE` field confirms this. For stateless applications, the Deployment spec is what persists, not the individual pod.

---

### 6. No Downtime

```bash
curl http://<route>/api/info   # returns 200 — application was never unavailable
```

---

## Closing Note

> The capabilities demonstrated in this session — S2I builds, canary deployments, self-healing, monitoring, and Operators — are production-deployed features, not experimental. The question for adoption is one of timing, not feasibility.

---

## Full Demo Recap

| Demonstrated | Outcome |
|---|---|
| Git URL → live HTTPS app (S2I) | Full build-deploy pipeline from source |
| Traffic split with weights | Zero-risk canary release pattern |
| Pod killed → auto-replaced | No manual recovery or alerting required |
| Prometheus scraping + probes | Observability and health management built in |
| HPA under real CPU load | Automatic horizontal scaling from metrics |
| Postgres Operator | Day-2 database operations encoded as automation |

---

## End of Demo

Suggested follow-up resources:

- **Red Hat Developer Sandbox** (free cluster): [developers.redhat.com/developer-sandbox](https://developers.redhat.com/developer-sandbox)
- **OpenShift Interactive Learning** (browser-based labs): [developers.redhat.com/learn](https://developers.redhat.com/learn)
- Internal next step: pilot project scoping session

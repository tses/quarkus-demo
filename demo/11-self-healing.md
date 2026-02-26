# ACT 3 — Self-Healing Pods

> **Script:** `scripts/11-self-healing.sh`
> **Goal:** Demonstrate the Kubernetes reconciliation loop — the platform detects a missing pod and replaces it automatically, with no manual intervention.

---

## Mental Model

OpenShift runs a continuous **reconciliation loop**:

```
Desired state:  3 pods running
Actual state:   2 pods running (one terminated)
Action:         Immediately schedule a replacement pod
```

> **Take away:** The platform does not wait for an alert, an on-call response, or a manual restart. It acts on the divergence between desired and actual state within seconds.

---

## Steps

### 1. Verify starting state — 3 pods running

Script 08 ends with 3 replicas. This demo starts directly from that state.

```bash
oc get pods -l app=ocp-demo-app -n ocp-demo
```

Confirm: all 3 pods show `Running` status and dark blue rings in **Topology**.

---

### 2. Prepare a split view

- **Left:** Topology view (visual — watch pod count change)
- **Right:** Terminal running the script

> **Tip:** The visual contrast between a missing pod ring and its replacement appearing is the clearest way to show the reconciliation cycle to an audience.

---

### 3. Delete a pod

The script highlights the target pod before deletion:

```
╔══════════════════════════════════════╗
║   KILLING POD: ocp-demo-app-xxx...   ║
╚══════════════════════════════════════╝
```

```bash
oc delete pod <pod-name> -n ocp-demo
```

Switch focus to the Topology view immediately after execution.

> **Goal:** The pod disappears from the topology. Within seconds, a replacement pod starts its initialisation cycle.

---

### 4. Observe recovery — live polling output

The script polls every 2 seconds for 30 seconds:

```
[t+2s]  Running pods: 2/3
[t+4s]  Running pods: 2/3
[t+6s]  Running pods: 3/3  ✅
```

> **Take away:** Total recovery time is typically under 10 seconds for a pre-pulled image. No human action was required at any point.

---

### 5. Confirm the replacement is a new pod

```bash
oc get pods -l app=ocp-demo-app -n ocp-demo
# NAME                        STATUS    RESTARTS   AGE
# ocp-demo-app-xxx-abc12      Running   0          14m
# ocp-demo-app-xxx-def34      Running   0          14m
# ocp-demo-app-xxx-xyz99      Running   0          9s   ← NEW
```

> **Gotcha:** The new pod has a different name — it is a genuinely new container, not a restart of the original. The `AGE` field confirms this. This distinction matters for stateless applications: the Deployment spec is what persists, not the individual pod.

---

### 6. Verify — no downtime

```bash
curl http://<route>/api/info   # returns 200 — application was never unavailable
```

---

## Closing Statement

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

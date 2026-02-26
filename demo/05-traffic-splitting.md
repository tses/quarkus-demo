# ACT 3 — Traffic Splitting

> **Script:** `scripts/05-traffic-splitting.sh`
> **Overview:** OpenShift Route weight splitting enables canary deployments — distributing live traffic across two versions simultaneously without additional infrastructure.

---

## Mental Model

**The problem:** A new version is ready. Full cutover carries risk. Staging environments do not reflect real production traffic patterns.

**The solution — Canary Deployment:**

- Route a small percentage of **real production traffic** to v2
- Observe metrics under real load
- Increase weight incrementally — or roll back instantly

> **Key point:** No extra infrastructure required. Traffic splitting is a native Route feature.

---

## Steps

### 1. Deploy v2

```bash
oc new-app \
  -i openshift/java:openjdk-17-ubi8 \
  --code=https://github.com/tses/quarkus-demo \
  --context-dir=app/ocp-demo-app \
  --name=ocp-demo-app-v2 \
  --labels=app=ocp-demo-app-v2,demo=ocp-intro,version=v2 \
  -n ocp-demo

# Distinguish v2 visually — /api/info returns "colour":"green"
oc set env deployment/ocp-demo-app-v2 \
  APP_COLOUR=green APP_VERSION=2.0.0 -n ocp-demo
```

Both deployments appear as separate nodes in **Topology**. v1 receives 100% of traffic until the route weights are updated.

---

### 2. Split: 90% v1 / 10% v2

```bash
oc patch route ocp-demo-app -n ocp-demo --type=merge -p '{
  "spec": {
    "to": {"kind":"Service","name":"ocp-demo-app","weight":90},
    "alternateBackends": [{"kind":"Service","name":"ocp-demo-app-v2","weight":10}]
  }
}'
```

Sending 20 requests shows the weighted distribution across both versions:

```
Request 1:  {"colour":"blue",...}   ← v1
Request 5:  {"colour":"green",...}  ← v2
...
v1 responses: 18/20  |  v2 responses: 2/20
```

> **Tip:** The `colour` field in the response distinguishes versions. The distribution across 20 requests reflects the 90/10 weight.

---

### 3. Move to 50/50

```bash
oc patch route ocp-demo-app -n ocp-demo --type=merge -p '{
  "spec": {
    "to": {"kind":"Service","name":"ocp-demo-app","weight":50},
    "alternateBackends": [{"kind":"Service","name":"ocp-demo-app-v2","weight":50}]
  }
}'
```

> **Key point:** At 50/50, metrics for both versions are available in **Observe → Dashboards**. Promotion to 100% should be based on error rates and latency.

---

### 4. Full Cutover to v2

```bash
oc patch route ocp-demo-app -n ocp-demo --type=merge -p '{
  "spec": {
    "to": {"kind":"Service","name":"ocp-demo-app-v2","weight":100},
    "alternateBackends": []
  }
}'
```

> **Key point:** Cutover is instantaneous. No users experience a request error during the transition.

---

### 5. Emergency Rollback to v1

```bash
oc patch route ocp-demo-app -n ocp-demo --type=merge -p '{
  "spec": {
    "to": {"kind":"Service","name":"ocp-demo-app","weight":100},
    "alternateBackends": []
  }
}'
```

> **Key point:** Rollback is a single patch operation. Traffic shifts immediately upon execution.

---

### 6. Cleanup — Remove v2 Resources

```bash
oc delete deployment,svc,bc,is ocp-demo-app-v2 -n ocp-demo --ignore-not-found
```

v2 resources are removed to avoid interfering with subsequent steps.

---

## Recap

| Action | Execution time | Risk exposure |
|---|---|---|
| Deploy v2 | Seconds | Zero — receives no traffic until weighted |
| Route 10% to v2 | 1 command | Minimal — 90% still on stable v1 |
| Graduate to 100% | Gradual — operator-controlled | Controlled |
| Rollback | 1 command | Immediate |

---

## ⬅️ Previous: [Deployment Strategies](04-deployment-strategies.md) | ➡️ Next: [Deploy Postgres Operator](06-operator-postgres.md)

# ACT 3 — Traffic Splitting

> **Script:** `scripts/05-traffic-splitting.sh`
> **Goal:** Demonstrate canary deployment using OpenShift Route weight splitting — live traffic distributed across two versions simultaneously.

---

## Mental Model

**The problem:** A new version is ready. Full cutover carries risk. Staging environments do not reflect real production traffic patterns.

**The solution — Canary Deployment:**

- Route a small percentage of **real production traffic** to v2
- Observe metrics under real load
- Increase weight incrementally — or roll back instantly

> **Take away:** No extra infrastructure required. Traffic splitting is a native Route feature.

---

## Steps

### 1. Deploy v2 (same source, different environment labels)

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

Both deployments appear as separate nodes in **Topology**.

> **Goal:** v1 is currently receiving 100% of traffic. The next steps shift that incrementally.

---

### 2. Split 90% v1 / 10% v2

```bash
oc patch route ocp-demo-app -n ocp-demo --type=merge -p '{
  "spec": {
    "to": {"kind":"Service","name":"ocp-demo-app","weight":90},
    "alternateBackends": [{"kind":"Service","name":"ocp-demo-app-v2","weight":10}]
  }
}'
```

The script sends **20 requests** and reports which version responded:

```
Request 1:  {"colour":"blue",...}   ← v1
Request 5:  {"colour":"green",...}  ← v2
...
v1 responses: 18/20  |  v2 responses: 2/20
```

> **Tip:** The response `colour` field distinguishes versions. Watch the distribution across 20 requests — it reflects the 90/10 weight.

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

> **Goal:** At this point, observe metrics for both versions in **Observe → Dashboards**. Only promote to 100% once error rates and latency are acceptable.

---

### 4. Full cutover to v2

```bash
oc patch route ocp-demo-app -n ocp-demo --type=merge -p '{
  "spec": {
    "to": {"kind":"Service","name":"ocp-demo-app-v2","weight":100},
    "alternateBackends": []
  }
}'
```

> **Take away:** Cutover is instantaneous from the platform's perspective. No users experienced a request error during the transition.

---

### 5. Emergency rollback (revert to v1)

```bash
oc patch route ocp-demo-app -n ocp-demo --type=merge -p '{
  "spec": {
    "to": {"kind":"Service","name":"ocp-demo-app","weight":100},
    "alternateBackends": []
  }
}'
```

> **Take away:** Rollback is a single patch operation. Traffic shifts immediately upon execution.

---

### 6. Cleanup — remove v2 resources

```bash
oc delete deployment,svc,bc,is ocp-demo-app-v2 -n ocp-demo --ignore-not-found
```

v2 resources are removed at script end to avoid interfering with subsequent demos.

---

## Recap

| Action | Execution time | Risk exposure |
|---|---|---|
| Deploy v2 | Seconds | Zero — receives no traffic until weighted |
| Route 10% to v2 | 1 command | Minimal — 90% still on stable v1 |
| Graduate to 100% | Gradual — operator-controlled | Controlled |
| Rollback | 1 command | Immediate |

---

## ➡️ Next: [Deploy Postgres Operator](06-operator-postgres.md)

# ACT 3 — Deployment Strategies

> **Script:** `scripts/04-deployment-strategies.sh`
> **Overview:** OpenShift supports rolling update and recreate deployment strategies, with built-in rollout history and one-command rollback.

---

## Mental Model

Two strategies — one critical behavioural difference:

```
RollingUpdate  → new pods UP before old pods DOWN  (zero downtime)
Recreate       → all old pods DOWN, then new pods UP (brief downtime — required for DB migrations)
```

> **Note:** The choice of strategy depends on application requirements. Stateless APIs use `RollingUpdate`. Singleton or schema-migration services require `Recreate`.

---

## Steps

### 1. Rolling Update — Parameters

Key parameters for `RollingUpdate`:

```
maxSurge: 25%        — maximum EXTRA pods allowed above desired count during update
                       (e.g. 4 replicas → up to 5 pods running simultaneously)

maxUnavailable: 25%  — maximum pods that may be unavailable during update
                       (e.g. 4 replicas → at least 3 always serving traffic)
```

> **Key point:** `maxSurge` and `maxUnavailable` together enforce the zero-downtime guarantee: new pods become healthy **before** old pods are terminated.

Inspect the live configuration:

```bash
oc get deployment ocp-demo-app -n ocp-demo \
  -o jsonpath='Strategy: {.spec.strategy.type}
MaxSurge: {.spec.strategy.rollingUpdate.maxSurge}
MaxUnavailable: {.spec.strategy.rollingUpdate.maxUnavailable}'
```

---

### 2. Triggering a Rollout

```bash
# Inject APP_VERSION — MicroProfile maps app.version → APP_VERSION
# /api/info returns the updated version value after rollout completes
oc set env deployment/ocp-demo-app APP_VERSION=v<timestamp> -n ocp-demo

# Record a human-readable CHANGE-CAUSE in rollout history
oc annotate deployment/ocp-demo-app \
  kubernetes.io/change-cause="demo rollout v<timestamp>" --overwrite -n ocp-demo
```

In the **Topology view**, old pods terminate only after new pods report healthy.

After rollout: `curl /api/info` returns the updated `"version"` field.

> **Tip:** Verify with `curl` after the rollout completes — the version change confirms end-to-end success.

---

### 3. Rollout History with CHANGE-CAUSE

```bash
oc rollout history deployment/ocp-demo-app -n ocp-demo
```

Each revision includes the `CHANGE-CAUSE` annotation — providing an auditable deployment log.

> **Key point:** Every deployment is recorded. Any revision can be targeted for rollback.

---

### 4. One-Command Rollback

```bash
oc rollout undo deployment/ocp-demo-app -n ocp-demo
```

> **Key point:** Instant rollback to the previous revision. No hotfix branch, no re-deploy pipeline.

---

### 5. Recreate Strategy

```yaml
strategy:
  type: Recreate          # ALL old pods stop first → THEN new pods start
                          # Use when two versions CANNOT run simultaneously
                          # (e.g. DB schema migration, singleton lock)
```

> **Note:** `Recreate` is the correct choice when running two versions of an application concurrently would corrupt data or violate a constraint — not a fallback for when `RollingUpdate` is "too complex".

---

## Recap

| Strategy | Downtime | Use when |
|---|---|---|
| `RollingUpdate` | Zero | Stateless apps, REST APIs |
| `Recreate` | Brief, controlled | DB migrations, singleton services |
| Rollback | Instant | Revert to previous known-good revision |

---

## ➡️ Next: [Traffic Splitting](05-traffic-splitting.md)

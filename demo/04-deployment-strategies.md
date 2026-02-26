# ACT 3 — Deployment Strategies

> **Script:** `scripts/04-deployment-strategies.sh`
> **Goal:** Demonstrate rolling update vs. recreate strategies, rollout history with change tracking, and one-command rollback.

---

## Mental Model

Two strategies — one critical behavioural difference:

```
RollingUpdate  → new pods UP before old pods DOWN  (zero downtime)
Recreate       → all old pods DOWN, then new pods UP (brief downtime — required for DB migrations)
```

> **Gotcha:** The question is not "which strategy is better". It is "what does your application require". Stateless APIs: `RollingUpdate`. Singleton or schema-migration services: `Recreate`.

---

## Steps

### 1. Review current strategy and explain the parameters

Key parameters for `RollingUpdate`:

```
maxSurge: 25%        — maximum EXTRA pods allowed above desired count during update
                       (e.g. 4 replicas → up to 5 pods running simultaneously)

maxUnavailable: 25%  — maximum pods that may be unavailable during update
                       (e.g. 4 replicas → at least 3 always serving traffic)
```

> **Take away:** `maxSurge` and `maxUnavailable` together enforce the zero-downtime guarantee: new pods become healthy **before** old pods are terminated.

Inspect the live configuration:

```bash
oc get deployment ocp-demo-app -n ocp-demo \
  -o jsonpath='Strategy: {.spec.strategy.type}
MaxSurge: {.spec.strategy.rollingUpdate.maxSurge}
MaxUnavailable: {.spec.strategy.rollingUpdate.maxUnavailable}'
```

---

### 2. Trigger a rollout — observe live in Topology

```bash
# Inject APP_VERSION — MicroProfile maps app.version → APP_VERSION
# /api/info returns the updated version value after rollout completes
oc set env deployment/ocp-demo-app APP_VERSION=v<timestamp> -n ocp-demo

# Record a human-readable CHANGE-CAUSE in rollout history
oc annotate deployment/ocp-demo-app \
  kubernetes.io/change-cause="demo rollout v<timestamp>" --overwrite -n ocp-demo
```

Switch to **Topology view** — old pods terminate only after new pods report healthy.

After rollout: `curl /api/info` returns the updated `"version"` field.

> **Tip:** Verify with `curl` after the rollout completes — the version change confirms end-to-end success.

---

### 3. Inspect rollout history with CHANGE-CAUSE

```bash
oc rollout history deployment/ocp-demo-app -n ocp-demo
```

Each revision shows the `CHANGE-CAUSE` annotation — providing an auditable deployment log.

> **Take away:** Every deployment is recorded. Any revision can be targeted for rollback.

---

### 4. One-command rollback

```bash
oc rollout undo deployment/ocp-demo-app -n ocp-demo
```

> **Take away:** Instant rollback to the previous revision. No hotfix branch, no re-deploy pipeline.

---

### 5. Recreate strategy (reference — not executed)

```yaml
strategy:
  type: Recreate          # ALL old pods stop first → THEN new pods start
                          # Use when two versions CANNOT run simultaneously
                          # (e.g. DB schema migration, singleton lock)
```

> **Gotcha:** `Recreate` is not a fallback for when `RollingUpdate` is "too complex". It is the correct choice when running two versions of an application concurrently would corrupt data or violate a constraint.

---

## Recap

| Strategy | Downtime | Use when |
|---|---|---|
| `RollingUpdate` | Zero | Stateless apps, REST APIs |
| `Recreate` | Brief, controlled | DB migrations, singleton services |
| Rollback | Instant | Revert to previous known-good revision |

---

## ➡️ Next: [Traffic Splitting](05-traffic-splitting.md)

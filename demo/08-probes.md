# ACT 3 — Liveness & Readiness Probes

> **Script:** `scripts/08-probes.sh`
> **Goal:** Understand the two probe types, their distinct failure actions, and how to configure them correctly.

---

## Mental Model

Two probes, two very different failure actions:

| Probe | Endpoint | Failure action |
|---|---|---|
| **Readiness** | `/q/health/ready` | Pod **removed from Service** — no traffic received, container keeps running |
| **Liveness** | `/q/health/live` | Container **killed and restarted** by kubelet — RESTARTS counter increments |

```
Readiness fail → "I am alive but not ready for traffic"
                 (e.g. warming up, dependency unavailable)

Liveness  fail → "I am stuck / deadlocked — please restart me"
                 (e.g. hung thread, infinite loop, corrupted state)
```

Both are implemented in the app via MicroProfile Health:

```java
@Liveness  @ApplicationScoped
class AppLiveness  implements HealthCheck { ... }  // → /q/health/live

@Readiness @ApplicationScoped
class AppReadiness implements HealthCheck { ... }  // → /q/health/ready
```

---

## Steps

### 1. Show state without probes

```bash
oc get deployment ocp-demo-app \
  -o jsonpath='{.spec.template.spec.containers[0].livenessProbe}'
# → empty — pod is marked Ready as soon as the container process starts
```

> **Gotcha:** Without a readiness probe, traffic arrives as soon as the container starts — even if the JVM hasn't finished initialising. The first few requests get connection-refused errors.

---

### 2. Probe configuration

```yaml
livenessProbe:
  httpGet:
    path: /q/health/live
    port: 8080
  initialDelaySeconds: 10   # let the JVM start before probing
  periodSeconds: 10
  failureThreshold: 3       # 3 consecutive failures → restart

readinessProbe:
  httpGet:
    path: /q/health/ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
  failureThreshold: 3       # 3 consecutive failures → remove from Service
```

> **Gotcha:** `initialDelaySeconds` must cover JVM startup. Set it too low and the pod enters a restart loop before the application has started — a common misconfiguration.

```bash
oc get deployment ocp-demo-app \
  -o jsonpath='{range .spec.template.spec.containers[*]}{.name}
  liveness : {.livenessProbe.httpGet.path}
  readiness: {.readinessProbe.httpGet.path}{end}'
```

**Console:** Workloads → Deployments → `ocp-demo-app` → YAML → scroll to `livenessProbe`.

---

### 3. What probe failures look like

**Readiness failure** (`oc get pods` + `oc get events`):

```bash
oc get pods -l app=ocp-demo-app -n ocp-demo
# NAME                        READY   STATUS    RESTARTS
# ocp-demo-app-xxx-yyy        0/1     Running   0   ← alive but NOT in Service

oc get events -n ocp-demo --sort-by='.lastTimestamp' | grep -i unhealthy
# Warning  Unhealthy  Readiness probe failed: HTTP probe failed with statuscode: 404
```

Note: `RESTARTS` stays at 0 — the container is alive, only removed from traffic.

**Liveness failure** (`oc describe pod`):

```
Warning  Unhealthy  Liveness probe failed: HTTP probe failed with statuscode: 503
Warning  Killing    Container demo-app failed liveness probe, will be restarted
Normal   Pulled     Successfully pulled image ...
Normal   Started    Started container demo-app
```

Key differences:

| | Readiness fail | Liveness fail |
|---|---|---|
| Container state | Running | Killed → restarted |
| RESTARTS counter | Unchanged | Increments |
| Traffic | Stopped | Stopped (during restart) |
| Recovery | Automatic when probe passes | Automatic **if** the root cause is fixed |

> **Gotcha:** A liveness probe that fires too aggressively (low `initialDelaySeconds`, low `failureThreshold`) will restart a healthy app that simply hasn't warmed up yet — causing CrashLoopBackOff on a perfectly good image.

> **CrashLoopBackOff:** Occurs when liveness keeps failing repeatedly. OCP applies exponential backoff (10s → 20s → 40s → … → 5 min cap). The restart loop does not self-heal a broken app — the root cause must be fixed.

---

## Recap

| Probe | Failure action | Analogy |
|---|---|---|
| Readiness | Removed from load balancer | "Temporarily closed" sign on the door |
| Liveness | Container killed + restarted | Emergency shutdown and reboot |

Both probes should always be configured for production workloads. Omitting them means:
- **No readiness** → users see errors during startup and slow rollouts
- **No liveness** → a hung container serves no traffic and is never recovered

---

## Key Commands

```bash
# Inspect probe configuration
oc get deployment ocp-demo-app \
  -o jsonpath='{.spec.template.spec.containers[0].livenessProbe}'

# Watch probe-related events
oc get events -n ocp-demo --sort-by='.lastTimestamp' | grep -i unhealthy

# Pod readiness status
oc get pods -l app=ocp-demo-app -n ocp-demo

# Full pod detail including probe status
oc describe pod <pod-name> -n ocp-demo
```

---

## ➡️ Next: [Monitoring — ServiceMonitor](09-monitoring.md)

# ACT 3 — Liveness & Readiness Probes

> **Script:** `scripts/09-probes.sh`
> **Goal:** Configure health probes, observe their distinct failure behaviours live, and understand why the distinction matters.

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

### 1. Verify the live health endpoints

```bash
curl http://<route>/q/health/live
# {"status":"UP","checks":[{"name":"app-live","status":"UP","data":{"hostname":"..."}}]}

curl http://<route>/q/health/ready
# {"status":"UP","checks":[{"name":"app-ready","status":"UP","data":{"status":"all systems nominal"}}]}
```

> **Tip:** These endpoints are served by the app itself. Kubernetes calls them periodically — any non-2xx response counts as a failure.

---

### 2. Show state without probes

```bash
oc get deployment ocp-demo-app \
  -o jsonpath='{.spec.template.spec.containers[0].livenessProbe}'
# → empty — pod is marked Ready as soon as the container process starts
```

> **Gotcha:** Without a readiness probe, traffic arrives as soon as the container starts — even if the JVM hasn't finished initialising. The first few requests get connection-refused errors.

---

### 3. Patch both probes

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

### 4. Live demo — readiness probe failure

Break the readiness probe by setting an invalid path:

```bash
oc patch deployment ocp-demo-app -n ocp-demo --type=json \
  -p '[{"op":"replace",
        "path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path",
        "value":"/bad"}]'
```

Observe the pod state:

```bash
oc get pods -l app=ocp-demo-app -n ocp-demo
# NAME                        READY   STATUS    RESTARTS
# ocp-demo-app-xxx-yyy        0/1     Running   0   ← alive but NOT in Service
```

Note: `RESTARTS` stays at 0 — the container is alive. Only traffic stops.

```bash
# Traffic is gone — the pod is no longer in Service endpoints
curl http://<route>/api/info
# → 503 Service Unavailable or connection refused

# Events confirm the failure
oc get events -n ocp-demo --sort-by='.lastTimestamp' | grep -i unhealthy
# Warning  Unhealthy  Readiness probe failed: HTTP probe failed with statuscode: 404
```

Restore the path — traffic returns within seconds:

```bash
oc patch deployment ocp-demo-app -n ocp-demo --type=json \
  -p '[{"op":"replace",
        "path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path",
        "value":"/q/health/ready"}]'
```

> **Take away:** The platform removed traffic from the broken pod and restored it automatically — no alerting pipeline, no manual endpoint update.

---

### 5. What a liveness failure looks like (reference)

```
Warning  Unhealthy  Liveness probe failed: HTTP probe failed with statuscode: 503
Warning  Killing    Container demo-app failed liveness probe, will be restarted
Normal   Pulled     Successfully pulled image ...
Normal   Started    Started container demo-app
```

Key differences vs readiness failure:

| | Readiness fail | Liveness fail |
|---|---|---|
| Container state | Running | Killed → restarted |
| RESTARTS counter | Unchanged | Increments |
| Traffic | Stopped | Stopped (during restart) |
| Recovery | Automatic when probe passes | Automatic **if** the root cause is fixed |

> **Gotcha:** A liveness probe that fires too aggressively (low `initialDelaySeconds`, low `failureThreshold`) will restart a healthy app that simply hasn't warmed up yet — causing CrashLoopBackOff on a perfectly good image.

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
```

---

## ➡️ Next: [Monitoring — ServiceMonitor](09-monitoring.md)

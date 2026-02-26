#!/usr/bin/env bash
# =============================================================================
# 08-probes.sh — Liveness & Readiness Probes: explain & show configuration
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/demo-config.sh"

header "ACT 3 — Liveness & Readiness Probes"

check_login
use_project

# ─────────────────────────────────────────────────────────────────────────────
# PART 1 — Mental model
# ─────────────────────────────────────────────────────────────────────────────
header "PART 1 — Two probes, two very different failure actions"

cat <<'MSG'
  ┌──────────────────┬─────────────────┬──────────────────────────────────────┐
  │ Probe            │ Endpoint        │ What happens when it FAILS            │
  ├──────────────────┼─────────────────┼──────────────────────────────────────┤
  │ Readiness        │ /q/health/ready │ Pod REMOVED from Service endpoints    │
  │                  │                 │ → traffic stops, pod keeps running    │
  ├──────────────────┼─────────────────┼──────────────────────────────────────┤
  │ Liveness         │ /q/health/live  │ Pod KILLED and restarted by kubelet   │
  │                  │                 │ → RESTARTS counter increments         │
  └──────────────────┴─────────────────┴──────────────────────────────────────┘

  Critical distinction:
    Readiness fail → "I am alive but not ready for traffic (e.g. warming up)"
    Liveness  fail → "I am stuck / deadlocked — please restart me"

  Both are implemented with MicroProfile Health in our Quarkus app:
    @Liveness  → /q/health/live
    @Readiness → /q/health/ready
MSG
echo ""
pause

# ─────────────────────────────────────────────────────────────────────────────
# PART 2 — Show current probe state (read-only)
# ─────────────────────────────────────────────────────────────────────────────
header "PART 2 — Current probe configuration on deployment/${APP_NAME}"

step "livenessProbe:"
echo ""
oc get deployment "${APP_NAME}" -n "${DEMO_PROJECT}" \
  -o jsonpath='{.spec.template.spec.containers[0].livenessProbe}' 2>/dev/null | \
  python3 -m json.tool 2>/dev/null || echo "  (no liveness probe configured)"
echo ""

step "readinessProbe:"
echo ""
oc get deployment "${APP_NAME}" -n "${DEMO_PROJECT}" \
  -o jsonpath='{.spec.template.spec.containers[0].readinessProbe}' 2>/dev/null | \
  python3 -m json.tool 2>/dev/null || echo "  (no readiness probe configured)"
echo ""

cat <<'MSG'
  Without a readiness probe: kubelet marks the pod Ready as soon as the container
  process starts — even if the JVM hasn't finished initialising yet.
  Traffic arrives and gets connection-refused errors during startup.
MSG
echo ""
pause

# ─────────────────────────────────────────────────────────────────────────────
# PART 3 — Probe configuration (reference YAML — explain, do not apply)
# ─────────────────────────────────────────────────────────────────────────────
header "PART 3 — How probes are configured"

cat <<'MSG'
  livenessProbe:
    httpGet:
      path: /q/health/live
      port: 8080
    initialDelaySeconds: 10   # wait for JVM startup before first probe
    periodSeconds: 10         # probe every 10 s
    failureThreshold: 3       # 3 consecutive failures → restart container

  readinessProbe:
    httpGet:
      path: /q/health/ready
      port: 8080
    initialDelaySeconds: 5
    periodSeconds: 5
    failureThreshold: 3       # 3 consecutive failures → remove from Service

  Key parameters:
    initialDelaySeconds  — must cover JVM/app startup time
                           too low → restart loop before the app has started
    failureThreshold     — prevents flapping on transient errors
MSG
echo ""
echo -e "  ${YELLOW}→ Console: Workloads → Deployments → ${APP_NAME} → YAML — scroll to livenessProbe${RESET}"
echo ""
pause

# ─────────────────────────────────────────────────────────────────────────────
# PART 4 — What failure events look like
# ─────────────────────────────────────────────────────────────────────────────
header "PART 4 — What probe failures look like in practice"

cat <<'MSG'
  Readiness probe failure (oc describe pod / oc get events):

    Warning  Unhealthy  Readiness probe failed: HTTP probe failed with statuscode: 404
    → pod stays in Running but READY column shows 0/1
    → pod is silently removed from Service endpoints
    → RESTARTS counter does NOT increment

  Liveness probe failure:

    Warning  Unhealthy  Liveness probe failed: HTTP probe failed with statuscode: 503
    Warning  Killing    Container demo-app failed liveness probe, will be restarted
    Normal   Pulled     Successfully pulled image ...
    Normal   Started    Started container demo-app
    → RESTARTS counter increments

  CrashLoopBackOff:
    Occurs when liveness keeps failing repeatedly.
    OCP applies exponential backoff: 10s → 20s → 40s → … → 5 min cap.
    Root cause must be fixed — the restart loop does not self-heal a broken app.

  Useful commands:
    oc get pods -l app=ocp-demo-app -n ocp-demo
    oc describe pod <pod-name> -n ocp-demo
    oc get events -n ocp-demo --sort-by='.lastTimestamp' | grep -i unhealthy
MSG
echo ""
pause

# ─────────────────────────────────────────────────────────────────────────────
# RECAP
# ─────────────────────────────────────────────────────────────────────────────
header "RECAP — Health Probes"

echo ""
echo -e "  ${BOLD}Readiness probe${RESET}  /q/health/ready  → traffic gate  (fail = removed from LB, pod stays up)"
echo -e "  ${BOLD}Liveness  probe${RESET}  /q/health/live   → health guard  (fail = restart by kubelet)"
echo ""
echo -e "  ${BOLD}initialDelaySeconds${RESET}  account for JVM/app startup time"
echo -e "  ${BOLD}failureThreshold${RESET}     consecutive failures before action (avoid flapping)"
echo ""
echo -e "  ${YELLOW}→ Console: Workloads → Deployments → ${APP_NAME} → YAML${RESET}"
echo ""
ok "Probes demo complete — next: Monitoring (09-monitoring.sh)"
echo ""

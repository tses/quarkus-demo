#!/usr/bin/env bash
# =============================================================================
# 08-probes.sh — Liveness & Readiness Probes: configure, break, and recover
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/demo-config.sh"

header "ACT 3 — Liveness & Readiness Probes"

check_login
use_project

ROUTE_URL=$(oc get route "${APP_NAME}" -n "${DEMO_PROJECT}" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

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
# PART 2 — See the live health responses
# ─────────────────────────────────────────────────────────────────────────────
header "PART 2 — Live health endpoint responses"

if [[ -n "${ROUTE_URL}" ]]; then
  step "GET /q/health/live:"
  echo ""
  curl -sf "http://${ROUTE_URL}/q/health/live" 2>/dev/null | python3 -m json.tool 2>/dev/null | sed 's/^/    /' || \
    echo "    (not reachable — verify the app is deployed and route exists)"
  echo ""

  step "GET /q/health/ready:"
  echo ""
  curl -sf "http://${ROUTE_URL}/q/health/ready" 2>/dev/null | python3 -m json.tool 2>/dev/null | sed 's/^/    /' || \
    echo "    (not reachable)"
  echo ""
else
  warn "No route found — skipping live curl demo"
  echo ""
fi
pause

# ─────────────────────────────────────────────────────────────────────────────
# PART 3 — Show current (no) probe state
# ─────────────────────────────────────────────────────────────────────────────
header "PART 3 — Current probe state (before configuration)"

step "Current livenessProbe on deployment/${APP_NAME}:"
echo ""
oc get deployment "${APP_NAME}" -n "${DEMO_PROJECT}" \
  -o jsonpath='{.spec.template.spec.containers[0].livenessProbe}' 2>/dev/null | \
  python3 -m json.tool 2>/dev/null || echo "  (no liveness probe configured)"
echo ""

step "Current readinessProbe on deployment/${APP_NAME}:"
echo ""
oc get deployment "${APP_NAME}" -n "${DEMO_PROJECT}" \
  -o jsonpath='{.spec.template.spec.containers[0].readinessProbe}' 2>/dev/null | \
  python3 -m json.tool 2>/dev/null || echo "  (no readiness probe configured)"
echo ""

cat <<'MSG'
  Without a readiness probe: kubelet marks the pod Ready as soon as the container
  process starts — even if the JVM hasn't finished initialising yet.
  Traffic arrives and gets connection-refused errors.
MSG
echo ""
pause

# ─────────────────────────────────────────────────────────────────────────────
# PART 4 — Patch probes
# ─────────────────────────────────────────────────────────────────────────────
header "PART 4 — Configure both probes"

step "Patching liveness + readiness probes onto deployment/${APP_NAME}:"
show_cmd "livenessProbe:
  httpGet:
    path: /q/health/live
    port: 8080
  initialDelaySeconds: 10   # wait for JVM startup
  periodSeconds: 10
  failureThreshold: 3       # 3 consecutive failures → restart

readinessProbe:
  httpGet:
    path: /q/health/ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
  failureThreshold: 3       # 3 consecutive failures → remove from Service"

oc patch deployment "${APP_NAME}" -n "${DEMO_PROJECT}" \
  --type=json \
  -p='[
    {
      "op": "replace",
      "path": "/spec/template/spec/containers/0/livenessProbe",
      "value": {
        "httpGet": {"path": "/q/health/live", "port": 8080},
        "initialDelaySeconds": 10,
        "periodSeconds": 10,
        "failureThreshold": 3
      }
    },
    {
      "op": "replace",
      "path": "/spec/template/spec/containers/0/readinessProbe",
      "value": {
        "httpGet": {"path": "/q/health/ready", "port": 8080},
        "initialDelaySeconds": 5,
        "periodSeconds": 5,
        "failureThreshold": 3
      }
    }
  ]'

echo ""
ok "Probes patched — rollout triggered"
wait_for_deployment "${APP_NAME}"
echo ""

step "Verify probes are configured:"
oc get deployment "${APP_NAME}" -n "${DEMO_PROJECT}" \
  -o jsonpath='{range .spec.template.spec.containers[*]}{.name}{"\n  liveness : "}{.livenessProbe.httpGet.path}{"\n  readiness: "}{.readinessProbe.httpGet.path}{"\n"}{end}'
echo ""
echo -e "  ${YELLOW}→ Console: Workloads → Deployments → ${APP_NAME} → YAML — scroll to livenessProbe${RESET}"
echo ""
pause

# ─────────────────────────────────────────────────────────────────────────────
# PART 5 — LIVE DEMO: break readiness probe → traffic stops → fix → traffic back
# ─────────────────────────────────────────────────────────────────────────────
header "PART 5 — Live demo: readiness probe failure"

cat <<'MSG'
  What we will do:
    1. Patch readiness probe to a non-existent path (/bad)
    2. Watch the pod go 0/1 Running  (alive but NOT in Service endpoints)
    3. Observe: curl returns connection errors → no traffic served
    4. Fix the path → pod returns to 1/1 → traffic restored

  This simulates: an app that is alive but not yet ready (DB not connected, cache warming, etc.)
MSG
echo ""
pause

step "Breaking readiness probe (path: /bad):"
show_cmd "oc patch deployment/${APP_NAME} --type=json
  -p '[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/readinessProbe/httpGet/path\",\"value\":\"/bad\"}]'"

oc patch deployment "${APP_NAME}" -n "${DEMO_PROJECT}" \
  --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/bad"}]'

echo ""
echo -e "  ${CYAN}Waiting ~20 s for rollout + probe failure to manifest...${RESET}"
sleep 5
oc rollout status deployment/"${APP_NAME}" -n "${DEMO_PROJECT}" --timeout=60s 2>/dev/null || true
echo ""

step "Pod state after readiness failure (expect 0/1 READY):"
echo ""
oc get pods -n "${DEMO_PROJECT}" -l "app=${APP_NAME}" --no-headers | \
  awk '{printf "  %-50s  READY=%s  STATUS=%s\n", $1, $2, $3}'
echo ""

if [[ -n "${ROUTE_URL}" ]]; then
  step "Attempting curl — should fail or return 503 (pod not in Service endpoints):"
  echo ""
  curl -sv --max-time 5 "http://${ROUTE_URL}/api/info" 2>&1 | \
    grep -E "< HTTP|Connection refused|503|upstream" | sed 's/^/    /' || \
    echo "    (connection refused or 503 — readiness probe working as intended)"
  echo ""
fi

step "Events confirming probe failure:"
echo ""
oc get events -n "${DEMO_PROJECT}" --sort-by='.lastTimestamp' 2>/dev/null | \
  grep -i "unhealthy\|readiness" | tail -5 | sed 's/^/  /' || \
  echo "  (events may take a moment to appear)"
echo ""
pause

step "Fixing readiness probe (restoring correct path /q/health/ready):"
show_cmd "oc patch deployment/${APP_NAME} --type=json
  -p '[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/readinessProbe/httpGet/path\",\"value\":\"/q/health/ready\"}]'"

oc patch deployment "${APP_NAME}" -n "${DEMO_PROJECT}" \
  --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/q/health/ready"}]'

wait_for_deployment "${APP_NAME}"
echo ""
ok "Pod back to 1/1 Ready — traffic restored"
echo ""

if [[ -n "${ROUTE_URL}" ]]; then
  echo "  Confirming traffic is back:"
  curl -sf "http://${ROUTE_URL}/api/info" 2>/dev/null | python3 -m json.tool 2>/dev/null | sed 's/^/    /' || \
    echo "    (app responding)"
  echo ""
fi
pause

# ─────────────────────────────────────────────────────────────────────────────
# PART 6 — What a failing liveness probe looks like
# ─────────────────────────────────────────────────────────────────────────────
header "PART 6 — What a liveness failure looks like (reference)"

cat <<'MSG'
  Events from oc describe pod when liveness fails:

    Warning  Unhealthy  Liveness probe failed: HTTP probe failed with statuscode: 503
    Warning  Killing    Container demo-app failed liveness probe, will be restarted
    Normal   Pulled     Successfully pulled image ...
    Normal   Started    Started container demo-app

  Key differences vs readiness failure:
    Readiness fail → pod stays running, just removed from Service (RESTARTS: 0)
    Liveness  fail → container is KILLED and restarted            (RESTARTS: N+1)

  CrashLoopBackOff occurs when liveness keeps failing repeatedly:
    OCP applies exponential backoff (10s → 20s → 40s → … → 5 min cap)
    Root cause must be fixed — the restart loop does not self-heal a broken app.
MSG
echo ""
pause

# ─────────────────────────────────────────────────────────────────────────────
# RECAP
# ─────────────────────────────────────────────────────────────────────────────
header "RECAP — Health Probes"

echo ""
echo -e "  ${BOLD}Readiness probe${RESET}  /q/health/ready  → traffic gate  (fail = removed from LB)"
echo -e "  ${BOLD}Liveness  probe${RESET}  /q/health/live   → health guard  (fail = restart by kubelet)"
echo ""
echo -e "  ${BOLD}initialDelaySeconds${RESET}  account for JVM/app startup time"
echo -e "  ${BOLD}failureThreshold${RESET}     consecutive failures before action (avoid flapping)"
echo ""
echo -e "  ${YELLOW}Both probes were demonstrated live — the platform removed traffic${RESET}"
echo -e "  ${YELLOW}from the broken pod automatically, with zero manual intervention.${RESET}"
echo ""
ok "Probes demo complete — next: Monitoring (09-monitoring.sh)"
echo ""

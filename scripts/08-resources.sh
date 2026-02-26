#!/usr/bin/env bash
# =============================================================================
# 08-resources.sh — Resource Requests & Limits: scheduling, throttling, OOMKill
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/demo-config.sh"

header "ACT 3 — Resource Requests & Limits"

check_login
use_project

ROUTE_URL=$(oc get route "${APP_NAME}" -n "${DEMO_PROJECT}" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

# ─────────────────────────────────────────────────────────────────────────────
# PART 1 — The mental model
# ─────────────────────────────────────────────────────────────────────────────
header "PART 1 — Mental model: requests vs limits"

cat <<'MSG'
  Every container has two independent knobs:

  ┌──────────────────┬───────────────────────────────────────────────────────────┐
  │ Field            │ Meaning                                                   │
  ├──────────────────┼───────────────────────────────────────────────────────────┤
  │ requests.cpu     │ Guaranteed CPU — scheduler uses this for node placement   │
  │ requests.memory  │ Guaranteed RAM — kubelet reserves this on the node        │
  │ limits.cpu       │ Hard cap — container is THROTTLED if it exceeds this      │
  │ limits.memory    │ Hard cap — container is OOMKilled if it exceeds this      │
  └──────────────────┴───────────────────────────────────────────────────────────┘

  QoS classes (eviction priority under node pressure):
    requests == limits  → Guaranteed  (last to be evicted)
    requests <  limits  → Burstable   (medium priority)
    neither set         → BestEffort  (first to be evicted)

  Key insight:
    • CPU over-limit → THROTTLED (container slows down, keeps running)
    • RAM over-limit → OOMKilled  (container is killed and restarted)
MSG
echo ""
pause

# ─────────────────────────────────────────────────────────────────────────────
# PART 2 — Show current (empty) state
# ─────────────────────────────────────────────────────────────────────────────
header "PART 2 — Current resource state (before we configure anything)"

step "Current resource configuration on deployment/${APP_NAME}:"
echo ""
oc get deployment "${APP_NAME}" -n "${DEMO_PROJECT}" \
  -o jsonpath='{.spec.template.spec.containers[0].resources}' 2>/dev/null | \
  python3 -m json.tool 2>/dev/null || echo "  (no resources set — BestEffort QoS)"
echo ""
echo -e "  ${YELLOW}With no limits: one noisy pod can consume ALL node CPU/RAM and starve neighbours.${RESET}"
echo ""
pause

# ─────────────────────────────────────────────────────────────────────────────
# PART 3 — Apply requests + limits
# ─────────────────────────────────────────────────────────────────────────────
header "PART 3 — Patch resource requests + limits"

step "Setting requests + limits on deployment/${APP_NAME}:"
show_cmd "oc set resources deployment/${APP_NAME} -n ${DEMO_PROJECT}
  --requests=cpu=100m,memory=512Mi
  --limits=cpu=1000m,memory=1024Mi"

oc patch deployment "${APP_NAME}" -n "${DEMO_PROJECT}" \
  --type=json \
  -p='[
    {
      "op": "replace",
      "path": "/spec/template/spec/containers/0/resources",
      "value": {
        "requests": {"cpu": "100m", "memory": "512Mi"},
        "limits":   {"cpu": "1000m", "memory": "1024Mi"}
      }
    }
  ]'

echo ""
ok "Resources patched — rollout triggered"
wait_for_deployment "${APP_NAME}"
echo ""

step "Verify:"
oc get deployment "${APP_NAME}" -n "${DEMO_PROJECT}" \
  -o jsonpath='{range .spec.template.spec.containers[*]}{.name}{"\n  requests: cpu="}{.resources.requests.cpu}{"  memory="}{.resources.requests.memory}{"\n  limits  : cpu="}{.resources.limits.cpu}{"  memory="}{.resources.limits.memory}{"\n"}{end}'
echo ""
pause

# ─────────────────────────────────────────────────────────────────────────────
# PART 4 — LIVE DEMO: CPU throttle via /api/burn
# ─────────────────────────────────────────────────────────────────────────────
header "PART 4 — Live demo: CPU limit in action"

cat <<'MSG'
  Strategy (two rounds — same workload, different CPU limit):

    Round 1 — limit = 1000m  (1 full core — generous)
      • /api/burn?seconds=60 runs in background
      • Pod gets up to 1 core → completes in ~60 s wall-clock time

    Round 2 — limit = 500m  (tight — half a core)
      • Same /api/burn?seconds=60 request
      • Kernel throttles the container to 0.5 core
      • Same burn takes noticeably longer (visible in oc adm top)
      • Pod stays ALIVE — throttling ≠ killing
MSG
echo ""
pause

# ── Round 1 — 1000m (already set by PART 3) ──────────────────────────────────
header "PART 4a — Round 1: CPU limit = 1000m (current setting)"

step "Current limit is already 1000m (set in PART 3). Confirm:"
oc get deployment "${APP_NAME}" -n "${DEMO_PROJECT}" \
  -o jsonpath='  cpu request={.spec.template.spec.containers[0].resources.requests.cpu}  limit={.spec.template.spec.containers[0].resources.limits.cpu}{"\n"}'
echo ""

if [[ -n "${ROUTE_URL}" ]]; then
  step "Firing /api/burn?seconds=60 with 1000m limit (background):"
  show_cmd "curl -s \"http://${ROUTE_URL}/api/burn?seconds=60\" &"
  curl -s "http://${ROUTE_URL}/api/burn?seconds=60" &
  BURN_PID=$!

  echo ""
  echo -e "  ${CYAN}Polling oc adm top pod every 5 s for 60 s — CPU should reach ~1000m:${RESET}"
  echo ""
  for i in $(seq 1 10); do
    sleep 5
    echo -n "  [t+$((i*5))s]  "
    oc adm top pod -n "${DEMO_PROJECT}" -l "app=${APP_NAME}" --no-headers 2>/dev/null || echo "(metrics warming up)"
  done
  # Let burn finish in background while we continue the demo
  wait "${BURN_PID}" 2>/dev/null || true
  echo ""
  ok "Round 1 done — burn completed quickly at 1000m limit"
else
  warn "No route found — skipping live burn demo"
fi
echo ""
pause

# ── Round 2 — 500m (tight) ────────────────────────────────────────────────────
header "PART 4b — Round 2: CPU limit = 500m (tight — demonstrating throttle)"

step "Tightening CPU limit to 500m:"
show_cmd "oc set resources deployment/${APP_NAME} -n ${DEMO_PROJECT}
  --requests=cpu=100m,memory=512Mi
  --limits=cpu=500m,memory=1024Mi"

oc patch deployment "${APP_NAME}" -n "${DEMO_PROJECT}" \
  --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources","value":{"requests":{"cpu":"100m","memory":"512Mi"},"limits":{"cpu":"500m","memory":"1024Mi"}}}]'

wait_for_deployment "${APP_NAME}"
echo ""

if [[ -n "${ROUTE_URL}" ]]; then
  step "Firing the SAME /api/burn?seconds=60 with 500m limit (background):"
  show_cmd "curl -s \"http://${ROUTE_URL}/api/burn?seconds=60\" &"
  curl -s "http://${ROUTE_URL}/api/burn?seconds=60" &
  BURN_PID=$!

  echo ""
  echo -e "  ${CYAN}Polling oc adm top pod every 5 s for 60 s — CPU is CAPPED at 500m:${RESET}"
  echo ""
  for i in $(seq 1 10); do
    sleep 5
    echo -n "  [t+$((i*5))s]  "
    oc adm top pod -n "${DEMO_PROJECT}" -l "app=${APP_NAME}" --no-headers 2>/dev/null || echo "(metrics warming up)"
  done
  wait "${BURN_PID}" 2>/dev/null || true
  echo ""
  ok "Round 2 done — pod kept running (throttled, not killed)"
  echo ""
  echo -e "  ${YELLOW}Key takeaway: same 60-second burn request took MUCH longer wall-clock${RESET}"
  echo -e "  ${YELLOW}time at 500m because the kernel limits CPU cycles given to the container.${RESET}"
else
  warn "No route found — skipping live burn demo"
fi
echo ""
pause

step "Restoring sensible CPU limit (1000m):"
show_cmd "oc set resources deployment/${APP_NAME} -n ${DEMO_PROJECT}
  --requests=cpu=100m,memory=512Mi
  --limits=cpu=1000m,memory=1024Mi"
oc patch deployment "${APP_NAME}" -n "${DEMO_PROJECT}" \
  --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources","value":{"requests":{"cpu":"100m","memory":"512Mi"},"limits":{"cpu":"1000m","memory":"1024Mi"}}}]'
wait_for_deployment "${APP_NAME}"
ok "Limits restored: cpu request=100m limit=1000m  memory=512Mi/1024Mi"
echo ""
pause

# ─────────────────────────────────────────────────────────────────────────────
# PART 5 — Namespace-level guardrails
# ─────────────────────────────────────────────────────────────────────────────
header "PART 5 — Namespace guardrails: LimitRange & ResourceQuota"

step "LimitRange — per-container defaults and maxima set by cluster admin:"
echo ""
oc get limitrange -n "${DEMO_PROJECT}" 2>/dev/null || echo "  (none configured in this namespace)"
echo ""

step "ResourceQuota — total budget for the entire namespace:"
echo ""
oc get resourcequota -n "${DEMO_PROJECT}" 2>/dev/null || echo "  (none configured in this namespace)"
echo ""

cat <<'MSG'
  LimitRange:   prevents a single container from using unlimited resources
                also injects default requests/limits if the developer omits them

  ResourceQuota: caps the TOTAL consumption of a namespace
                 e.g. "this team's namespace may not exceed 4 CPU / 8Gi RAM total"
MSG
echo ""
pause

# ─────────────────────────────────────────────────────────────────────────────
# RECAP
# ─────────────────────────────────────────────────────────────────────────────
header "RECAP — Resource Requests & Limits"

echo ""
echo -e "  ${BOLD}requests${RESET}  → scheduling guarantee (scheduler picks a node that can honour this)"
echo -e "  ${BOLD}limits  ${RESET}  → enforcement ceiling  (CPU: throttle / RAM: OOMKill + restart)"
echo ""
echo -e "  ${BOLD}CPU over limit${RESET}   → container SLOWS DOWN  (stays alive)"
echo -e "  ${BOLD}RAM over limit${RESET}   → container is KILLED   (RESTARTS counter increments)"
echo ""
echo -e "  ${BOLD}QoS${RESET}: requests==limits → Guaranteed (best for production)"
echo ""
echo -e "  ${YELLOW}→ Console: Observe → Dashboards → Kubernetes/Compute Resources/Namespace (Pods)${RESET}"
echo -e "  ${YELLOW}  Each pod bar shows: actual / request / limit${RESET}"
echo ""
ok "Resources demo complete — next: Monitoring (09-monitoring.sh)"
echo ""

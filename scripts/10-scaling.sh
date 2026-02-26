#!/usr/bin/env bash
# =============================================================================
# 10-scaling.sh — Manual scale + HPA auto-scaling demo
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/demo-config.sh"

header "ACT 3 — Scaling Out"

check_login
use_project

# ── Step 1: Show current replicas ────────────────────────────────────────────
step "Current state — 1 pod:"
oc get pods -n "${DEMO_PROJECT}" -l "app=${APP_NAME}" --no-headers | \
  awk '{print "  " $1 "\t" $3}'
echo ""
pause

# ── Step 2: Manual scale UP ──────────────────────────────────────────────────
step "Scaling to 3 replicas (manual):"
echo -e "${YELLOW}  Watch Topology view — 3 pods will appear${RESET}"
show_cmd "oc scale deployment/${APP_NAME} --replicas=3 -n ${DEMO_PROJECT}"
oc scale deployment/"${APP_NAME}" --replicas=3 -n "${DEMO_PROJECT}"

# Watch pods come up
oc get pods -n "${DEMO_PROJECT}" -l "app=${APP_NAME}" -w &
WATCH_PID=$!
sleep 10
kill "${WATCH_PID}" 2>/dev/null || true

wait_for_deployment "${APP_NAME}"
echo ""
ok "3 pods running — traffic is load-balanced across all of them"

# Show the 3 pods
oc get pods -n "${DEMO_PROJECT}" -l "app=${APP_NAME}" --no-headers | \
  awk '{print "  " $1 "\t" $3 "\t" $5}'
echo ""
pause

# ── Step 3: Show load balancing — different pod names in each response ────────
step "Demonstrating load balancing (/api/info shows hostname = pod name):"
ROUTE_URL=$(oc get route "${APP_NAME}" -n "${DEMO_PROJECT}" -o jsonpath='{.spec.host}' 2>/dev/null || \
            oc get route "${APP_NAME_V2}" -n "${DEMO_PROJECT}" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

if [[ -n "${ROUTE_URL}" ]]; then
  for i in $(seq 1 6); do
    RESP=$(curl -sf "http://${ROUTE_URL}/api/info" 2>/dev/null || echo "no response")
    # Extract just hostname for compact display
    HOST=$(echo "${RESP}" | grep -o '"hostname":"[^"]*"' | cut -d'"' -f4 || echo "${RESP}")
    echo -e "  Request ${i}: pod = ${CYAN}${BOLD}${HOST}${RESET}"
  done
fi
echo ""
pause

# ── Step 4: Scale DOWN ───────────────────────────────────────────────────────
step "Scaling back to 1 replica:"
show_cmd "oc scale deployment/${APP_NAME} --replicas=1 -n ${DEMO_PROJECT}"
oc scale deployment/"${APP_NAME}" --replicas=1 -n "${DEMO_PROJECT}"
wait_for_deployment "${APP_NAME}"
ok "Back to 1 pod"
echo ""
pause

# ── Step 5: Configure HPA ────────────────────────────────────────────────────
step "Setting up Horizontal Pod Autoscaler (HPA):"
echo ""
cat << 'EOF'
  Rule: if CPU > 50% → scale up (max 5 pods)
        if CPU < 50% → scale down (min 1 pod)
EOF
echo ""

# Remove existing HPA if any
oc delete hpa "${APP_NAME}" -n "${DEMO_PROJECT}" 2>/dev/null || true

show_cmd "oc autoscale deployment/${APP_NAME}
  --min=1 --max=5 --cpu-percent=50
  -n ${DEMO_PROJECT}"
oc autoscale deployment/"${APP_NAME}" \
  --min=1 \
  --max=5 \
  --cpu-percent=50 \
  -n "${DEMO_PROJECT}"

echo ""
ok "HPA created"
sleep 3
oc get hpa "${APP_NAME}" -n "${DEMO_PROJECT}"
echo ""
pause

# ── Step 6: Trigger CPU burn to show HPA in action ───────────────────────────
step "Triggering CPU load with parallel clients — watch HPA react:"
echo ""
echo -e "${YELLOW}  10 parallel clients, each calling /api/burn?seconds=90 with 1s delay${RESET}"
echo -e "${YELLOW}  This sustains CPU pressure long enough for HPA to trigger a scale-up${RESET}"
echo -e "${YELLOW}  Watch: oc get hpa -w   and   oc get pods -w${RESET}"
echo ""

if [[ -n "${ROUTE_URL}" ]]; then
  PARALLEL_CLIENTS=10
  BURN_SECONDS=90
  LOAD_DURATION=120   # total seconds to keep firing new requests

  # Launch parallel background workers — each loops until LOAD_DURATION elapses
  LOAD_PIDS=()
  LOAD_START=$(date +%s)
  for c in $(seq 1 "${PARALLEL_CLIENTS}"); do
    (
      while true; do
        NOW=$(date +%s)
        if (( NOW - LOAD_START >= LOAD_DURATION )); then break; fi
        curl -sf "http://${ROUTE_URL}/api/burn?seconds=${BURN_SECONDS}" \
          -o /dev/null 2>/dev/null || true
        sleep 1
      done
    ) &
    LOAD_PIDS+=($!)
    # Stagger startup slightly so not all clients hit simultaneously
    sleep 0.1
  done

  echo -e "  ${GREEN}${PARALLEL_CLIENTS} load clients started (PIDs: ${LOAD_PIDS[*]})${RESET}"
  echo ""

  # Watch pods scale up while load runs
  step "Watching pods scale up (updating every 5s for ${LOAD_DURATION}s):"
  ELAPSED=0
  while (( ELAPSED < LOAD_DURATION )); do
    echo -ne "  [t+${ELAPSED}s] "
    oc get pods -n "${DEMO_PROJECT}" -l "app=${APP_NAME}" --no-headers 2>/dev/null | \
      awk '{printf "%s(%s) ", $1, $3}' || true
    echo ""
    sleep 5
    ELAPSED=$((ELAPSED + 5))
  done

  # Stop all load clients
  for pid in "${LOAD_PIDS[@]}"; do
    kill "${pid}" 2>/dev/null || true
  done
  echo ""
  ok "Load generation stopped."
fi

echo ""
step "HPA status after burn:"
oc get hpa "${APP_NAME}" -n "${DEMO_PROJECT}"
echo ""
echo -e "${YELLOW}  Pods will scale back down after CPU drops (cool-down ~5 min).${RESET}"
echo ""
ok "HPA / autoscaling demo complete."
pause

# ── Cleanup: remove HPA and reset to 3 replicas for the next demo ────────────
step "Cleaning up — removing HPA and resetting to 3 replicas..."
show_cmd "oc delete hpa ${APP_NAME} -n ${DEMO_PROJECT} --ignore-not-found
oc scale deployment/${APP_NAME} --replicas=3 -n ${DEMO_PROJECT}"
oc delete hpa "${APP_NAME}" -n "${DEMO_PROJECT}" --ignore-not-found 2>/dev/null || true
oc scale deployment/"${APP_NAME}" --replicas=3 -n "${DEMO_PROJECT}"
wait_for_deployment "${APP_NAME}"
ok "HPA removed — deployment reset to 3 replicas. Ready for the next demo."

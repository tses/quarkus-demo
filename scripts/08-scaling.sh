#!/usr/bin/env bash
# =============================================================================
# 08-scaling.sh — Manual scale + HPA auto-scaling demo
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
echo ""
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
step "Triggering CPU burn on the pod — watch HPA react:"
echo ""
echo -e "${YELLOW}  Calling /api/burn?seconds=60 — this saturates all CPU cores${RESET}"
echo -e "${YELLOW}  Watch: oc get hpa -w   and   oc get pods -w${RESET}"
echo ""

if [[ -n "${ROUTE_URL}" ]]; then
  # Fire burn in background (non-blocking so we can watch pods)
  curl -sf "http://${ROUTE_URL}/api/burn?seconds=60" &
  BURN_PID=$!

  # Watch pods scale up for 90 seconds
  step "Watching pods (Ctrl+C to stop):"
  timeout 90 oc get pods -n "${DEMO_PROJECT}" -l "app=${APP_NAME}" -w 2>/dev/null || true

  wait "${BURN_PID}" 2>/dev/null || true
fi

echo ""
step "HPA status after burn:"
oc get hpa "${APP_NAME}" -n "${DEMO_PROJECT}"
echo ""
echo -e "${YELLOW}  Pods will scale back down after CPU drops (cool-down ~5 min).${RESET}"
echo ""
ok "HPA / autoscaling demo complete."

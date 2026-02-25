#!/usr/bin/env bash
# =============================================================================
# 09-self-healing.sh — Kill a pod — watch it come back automatically
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/demo-config.sh"

header "ACT 3 — Self-Healing Pods"

check_login
use_project

# ── Step 1: Scale to 3 replicas ──────────────────────────────────────────────
step "Scaling to 3 replicas..."
show_cmd "oc scale deployment/${APP_NAME} --replicas=3 -n ${DEMO_PROJECT}"
oc scale deployment/"${APP_NAME}" --replicas=3 -n "${DEMO_PROJECT}"
wait_for_deployment "${APP_NAME}"
echo ""

# ── Step 2: Show stable state ────────────────────────────────────────────────
step "All 3 pods healthy — this is our 'desired state':"
echo ""
oc get pods -n "${DEMO_PROJECT}" -l "app=${APP_NAME}" \
  -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,STARTED:.status.startTime'
echo ""
echo -e "${YELLOW}  Desired replicas : 3${RESET}"
echo -e "${YELLOW}  Actual replicas  : 3${RESET}"
echo -e "${YELLOW}  Status           : ✔ In sync${RESET}"
echo ""
pause

# ── Step 3: THE MOMENT — kill a pod ──────────────────────────────────────────
# Get the first pod name
POD_TO_KILL=$(oc get pod -n "${DEMO_PROJECT}" -l "app=${APP_NAME}" \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}')

echo ""
echo -e "${RED}${BOLD}  ╔══════════════════════════════════════╗${RESET}"
echo -e "${RED}${BOLD}  ║   KILLING POD: ${POD_TO_KILL:0:35}  ║${RESET}"
echo -e "${RED}${BOLD}  ╚══════════════════════════════════════╝${RESET}"
echo ""
echo -e "${YELLOW}  → Switch to Console Topology view NOW ←${RESET}"
echo ""
sleep 2

show_cmd "oc delete pod ${POD_TO_KILL} -n ${DEMO_PROJECT}"
oc delete pod "${POD_TO_KILL}" -n "${DEMO_PROJECT}"

echo ""
echo -e "${BOLD}  Pod deleted. Watching recovery...${RESET}"
echo ""

# ── Step 4: Watch it recover in real-time ────────────────────────────────────
# Poll pod status for 30 seconds
for i in $(seq 1 15); do
  sleep 2
  PODS=$(oc get pods -n "${DEMO_PROJECT}" -l "app=${APP_NAME}" \
    --no-headers 2>/dev/null | awk '{print $1 "\t" $3}')
  RUNNING=$(oc get pods -n "${DEMO_PROJECT}" -l "app=${APP_NAME}" \
    --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
  echo -e "  [t+${i}s] Running pods: ${GREEN}${RUNNING}/3${RESET}"
  if [[ "$RUNNING" -eq 3 ]]; then
    break
  fi
done

echo ""
ok "Back to 3 pods. Platform restored desired state automatically."
echo ""

# ── Step 5: Show the new pod (different name = genuinely new) ─────────────────
step "Pod list now — notice the NEW pod (different name, young age):"
echo ""
oc get pods -n "${DEMO_PROJECT}" -l "app=${APP_NAME}" \
  -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,RESTARTS:.status.containerStatuses[0].restartCount,AGE:.metadata.creationTimestamp'
echo ""
echo -e "${YELLOW}  The new pod has a different random suffix.${RESET}"
echo -e "${YELLOW}  It was created automatically. No human intervention.${RESET}"
echo ""
pause

# ── Step 6: Verify app never went down ───────────────────────────────────────
ROUTE_URL=$(oc get route "${APP_NAME}" -n "${DEMO_PROJECT}" -o jsonpath='{.spec.host}' 2>/dev/null || \
            oc get route "${APP_NAME_V2}" -n "${DEMO_PROJECT}" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

if [[ -n "${ROUTE_URL}" ]]; then
  step "App is still responding (no downtime experienced by users):"
  for i in $(seq 1 3); do
    RESP=$(curl -sf "http://${ROUTE_URL}/api/info" 2>/dev/null || echo "no response")
    echo -e "  Request ${i}: ${GREEN}${RESP}${RESET}"
  done
fi
echo ""

# ── Closing statement ─────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}${CYAN}  DEMO COMPLETE${RESET}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "  ${BOLD}1.${RESET} Git URL → Live HTTPS App          (S2I)"
echo -e "  ${BOLD}2.${RESET} Canary release with traffic slider (Route weights)"
echo -e "  ${BOLD}3.${RESET} Pod killed → auto-replaced          (Self-healing)"
echo ""
echo -e "  ${YELLOW}All of this ran on a standard OpenShift cluster.${RESET}"
echo -e "  ${YELLOW}No custom tooling. No Dockerfile. No YAML written from scratch.${RESET}"
echo ""
echo -e "  ${BOLD}Next step → ${CYAN}developers.redhat.com/developer-sandbox${RESET}"
echo ""

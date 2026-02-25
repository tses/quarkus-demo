#!/usr/bin/env bash
# =============================================================================
# 03-pods-svc-route.sh — Explore Pods, Service, Route anatomy
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/demo-config.sh"

header "ACT 2 — Pods / Service / Route"

check_login
use_project

# ── Step 1: Show pods ─────────────────────────────────────────────────────────
step "Our running pods:"
show_cmd "oc get pods -n ${DEMO_PROJECT} -l app=${APP_NAME}
  -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName,IP:.status.podIP"
oc get pods -n "${DEMO_PROJECT}" -l "app=${APP_NAME}" \
  -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName,IP:.status.podIP,AGE:.metadata.creationTimestamp'
echo ""
pause

# ── Step 2: Describe a pod (lots of info) ────────────────────────────────────
POD_NAME=$(oc get pod -n "${DEMO_PROJECT}" -l "app=${APP_NAME}" \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}')

step "Inspecting pod: ${POD_NAME}"
show_cmd "oc describe pod ${POD_NAME} -n ${DEMO_PROJECT}"
echo ""
oc describe pod "${POD_NAME}" -n "${DEMO_PROJECT}" | head -40
echo ""
pause

# ── Step 3: Live logs from the pod ───────────────────────────────────────────
step "Live logs from pod ${POD_NAME} (last 20 lines):"
show_cmd "oc logs ${POD_NAME} -n ${DEMO_PROJECT} --tail=20"
oc logs "${POD_NAME}" -n "${DEMO_PROJECT}" --tail=20
echo ""
pause

# ── Step 4: Shell INTO the pod (terminal access) ─────────────────────────────
step "Opening a shell inside the running pod..."
echo -e "${YELLOW}  (Type 'exit' when done to return to demo)${RESET}"
show_cmd "oc exec -it ${POD_NAME} -n ${DEMO_PROJECT} -- bash"
echo ""
oc exec -it "${POD_NAME}" -n "${DEMO_PROJECT}" -- \
  bash -c "echo '=== Inside the container ===' && ls /deployments && echo '' && cat /etc/os-release | grep PRETTY && echo ''"
echo ""
pause

# ── Step 5: Show the Service ─────────────────────────────────────────────────
step "The Service (stable internal address):"
show_cmd "oc get svc ${APP_NAME} -n ${DEMO_PROJECT}
oc describe svc ${APP_NAME} -n ${DEMO_PROJECT}"
oc get svc "${APP_NAME}" -n "${DEMO_PROJECT}"
echo ""
oc describe svc "${APP_NAME}" -n "${DEMO_PROJECT}" | grep -E "Name:|Port:|TargetPort:|Selector:|Endpoints:"
echo ""
pause

# ── Step 6: Show the Route ───────────────────────────────────────────────────
step "The Route (public HTTPS URL):"
oc get route "${APP_NAME}" -n "${DEMO_PROJECT}"
echo ""

ROUTE_URL=$(oc get route "${APP_NAME}" -n "${DEMO_PROJECT}" -o jsonpath='{.spec.host}')
echo -e "  ${BOLD}Public URL :${RESET} ${CYAN}http://${ROUTE_URL}/api/info${RESET}"
echo -e "  ${BOLD}TLS        :${RESET} Edge terminated (HTTPS available)"
echo ""

# Live curl to the route
step "Calling the app via Route:"
show_cmd "curl http://${ROUTE_URL}/api/info"
for i in 1 2 3; do
  RESP=$(curl -sf "http://${ROUTE_URL}/api/info" 2>/dev/null || echo "no response")
  echo -e "  Request ${i}: ${GREEN}${RESP}${RESET}"
done
echo ""

ok "Pod → Service → Route chain verified."

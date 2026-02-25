#!/usr/bin/env bash
# =============================================================================
# 05-traffic-splitting.sh — WOW #2: Canary release with traffic weights
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/demo-config.sh"

header "ACT 3 — Traffic Splitting ⭐ WOW #2"

check_login
use_project

ROUTE_URL=$(oc get route "${APP_NAME}" -n "${DEMO_PROJECT}" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
if [[ -z "${ROUTE_URL}" ]]; then
  warn "Route for ${APP_NAME} not found. Run 02-deploy-s2i.sh first."
  exit 1
fi

# ── Step 1: Deploy v2 (same source, different env label so we can identify it) ─
step "Deploying v2 of the app (new colour/label to identify responses)..."
echo ""

# Deploy v2 using the same builder image — explicit to avoid auto-detect errors
oc new-app \
  -i "openshift/${BUILDER_IMAGE}" \
  --code="${GIT_REPO}" \
  --context-dir="${GIT_CONTEXT_DIR}" \
  --name="${APP_NAME_V2}" \
  --labels="app=${APP_NAME_V2},demo=ocp-intro,version=v2" \
  -n "${DEMO_PROJECT}" 2>/dev/null || true

# Patch v2 with APP_COLOUR=green so /api/info clearly shows "colour":"green"
oc set env deployment/"${APP_NAME_V2}" \
  APP_COLOUR="green" \
  APP_VERSION="2.0.0" \
  -n "${DEMO_PROJECT}" 2>/dev/null || true

step "Waiting for v2 build to complete..."
# Wait for the Build object to exist, then tail its logs
sleep 5
oc logs -f "bc/${APP_NAME_V2}" -n "${DEMO_PROJECT}" 2>/dev/null || true

step "Waiting for v2 deployment to be ready..."
# Poll until the Deployment exists (created only after build succeeds)
for i in $(seq 1 60); do
  if oc get deployment "${APP_NAME_V2}" -n "${DEMO_PROJECT}" &>/dev/null; then
    break
  fi
  sleep 5
done
wait_for_deployment "${APP_NAME_V2}"

ok "v2 is running (but receiving no traffic yet)"
pause

# ── Step 2: 100% traffic to v1 (baseline) ────────────────────────────────────
step "Current state: 100% traffic → v1"
echo ""
for i in $(seq 1 5); do
  RESP=$(curl -sf "http://${ROUTE_URL}/api/info" 2>/dev/null || echo "no response")
  echo -e "  Request ${i}: ${CYAN}${RESP}${RESET}"
done
echo ""
pause

# ── Step 3: Split 90/10 ───────────────────────────────────────────────────────
step "Setting traffic split: 90% → v1, 10% → v2"
oc patch route "${APP_NAME}" -n "${DEMO_PROJECT}" \
  --type=merge \
  -p "{
    \"spec\": {
      \"to\": {
        \"kind\": \"Service\",
        \"name\": \"${APP_NAME}\",
        \"weight\": 90
      },
      \"alternateBackends\": [{
        \"kind\": \"Service\",
        \"name\": \"${APP_NAME_V2}\",
        \"weight\": 10
      }]
    }
  }"
ok "90/10 split active"
echo ""

step "Sending 20 requests — watch v2 (green) appear occasionally:"
V1_COUNT=0; V2_COUNT=0
for i in $(seq 1 20); do
  RESP=$(curl -sf "http://${ROUTE_URL}/api/info" 2>/dev/null || echo "no response")
  if [[ "${RESP}" == *'"colour":"green"'* ]] || [[ "${RESP}" == *'"colour": "green"'* ]]; then
    echo -e "  Request ${i}: ${YELLOW}${BOLD}${RESP}${RESET}  ← v2 (green)"
    ((V2_COUNT++))
  else
    echo -e "  Request ${i}: ${CYAN}${RESP}${RESET}  ← v1 (blue)"
    ((V1_COUNT++))
  fi
done
echo ""
echo -e "  v1 responses: ${GREEN}${V1_COUNT}/20${RESET}  |  v2 responses: ${YELLOW}${V2_COUNT}/20${RESET}"
pause

# ── Step 4: Move to 50/50 ────────────────────────────────────────────────────
step "Increasing v2 traffic to 50%..."
oc patch route "${APP_NAME}" -n "${DEMO_PROJECT}" \
  --type=merge \
  -p "{
    \"spec\": {
      \"to\": {\"kind\":\"Service\",\"name\":\"${APP_NAME}\",\"weight\":50},
      \"alternateBackends\": [{\"kind\":\"Service\",\"name\":\"${APP_NAME_V2}\",\"weight\":50}]
    }
  }"
ok "50/50 split active — monitoring..."
echo ""

step "Sending 10 requests at 50/50:"
for i in $(seq 1 10); do
  RESP=$(curl -sf "http://${ROUTE_URL}/api/info" 2>/dev/null || echo "no response")
  if [[ "${RESP}" == *'"colour":"green"'* ]] || [[ "${RESP}" == *'"colour": "green"'* ]]; then
    echo -e "  Request ${i}: ${YELLOW}${BOLD}${RESP}${RESET}  ← v2 (green)"
  else
    echo -e "  Request ${i}: ${CYAN}${RESP}${RESET}  ← v1 (blue)"
  fi
done
pause

# ── Step 5: Full cutover to v2 ───────────────────────────────────────────────
step "All good — cutting over 100% to v2!"
oc patch route "${APP_NAME}" -n "${DEMO_PROJECT}" \
  --type=merge \
  -p "{
    \"spec\": {
      \"to\": {\"kind\":\"Service\",\"name\":\"${APP_NAME_V2}\",\"weight\":100},
      \"alternateBackends\": []
    }
  }"
ok "100% traffic → v2. Cutover complete. Zero downtime."
echo ""

step "Verify — all requests now hit v2 (colour=green):"
for i in $(seq 1 5); do
  RESP=$(curl -sf "http://${ROUTE_URL}/api/info" 2>/dev/null || echo "no response")
  echo -e "  Request ${i}: ${YELLOW}${BOLD}${RESP}${RESET}"
done
echo ""
pause

# ── Step 6 (optional): Emergency rollback ────────────────────────────────────
step "Emergency rollback demo (back to v1 instantly):"
oc patch route "${APP_NAME}" -n "${DEMO_PROJECT}" \
  --type=merge \
  -p "{
    \"spec\": {
      \"to\": {\"kind\":\"Service\",\"name\":\"${APP_NAME}\",\"weight\":100},
      \"alternateBackends\": []
    }
  }"
ok "Rollback done. 100% back to v1."
echo ""
RESP=$(curl -sf "http://${ROUTE_URL}/api/info" 2>/dev/null || echo "no response")
echo -e "  Verify (colour should be blue): ${CYAN}${RESP}${RESET}"
echo ""
ok "Traffic splitting demo complete. ⭐"

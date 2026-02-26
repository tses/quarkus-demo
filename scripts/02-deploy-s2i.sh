#!/usr/bin/env bash
# =============================================================================
# 02-deploy-s2i.sh — Deploy Quarkus app from Git using S2I
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/demo-config.sh"

header "ACT 2 — Deploy with S2I"

check_login
use_project

# ── Step 1: Show the git repo (reminder to have browser tab open) ─────────────
step "App source: ${GIT_REPO} (context: ${GIT_CONTEXT_DIR})"
echo ""
echo -e "  ${BOLD}Git URL   :${RESET} ${CYAN}${GIT_REPO}${RESET}"
echo -e "  ${BOLD}Sub-dir   :${RESET} ${CYAN}${GIT_CONTEXT_DIR}${RESET}"
echo -e "  ${BOLD}Framework :${RESET} Quarkus (Java 17, RESTEasy Reactive)"
echo ""
echo -e "  ${BOLD}Endpoints :${RESET}"
echo -e "    ${CYAN}GET /api/info${RESET}            — hostname (pod name), version, colour"
echo -e "    ${CYAN}GET /api/burn?seconds=30${RESET} — CPU stress → triggers HPA"
echo -e "    ${CYAN}GET /q/health${RESET}            — liveness + readiness probes"
echo -e "    ${CYAN}GET /q/metrics${RESET}           — Prometheus metrics"
echo -e "    ${CYAN}GET /swagger-ui${RESET}          — OpenAPI UI"
echo ""
pause

# ── Step 2: new-app from source ───────────────────────────────────────────────
step "Running: oc new-app (S2I from Git)..."
show_cmd "oc new-app
  -i openshift/${BUILDER_IMAGE}
  --code=${GIT_REPO}
  --context-dir=${GIT_CONTEXT_DIR}
  --name=${APP_NAME}
  --labels=app=${APP_NAME},demo=ocp-intro
  -n ${DEMO_PROJECT}"
oc new-app \
  -i "openshift/${BUILDER_IMAGE}" \
  --code="${GIT_REPO}" \
  --context-dir="${GIT_CONTEXT_DIR}" \
  --name="${APP_NAME}" \
  --labels="app=${APP_NAME},demo=ocp-intro" \
  -n "${DEMO_PROJECT}"

ok "Build triggered! Watching build logs..."
echo ""

# ── Step 3: Tail build logs ───────────────────────────────────────────────────
step "Build logs (S2I compiling and packaging the app):"
show_cmd "oc logs -f bc/${APP_NAME}
  -n ${DEMO_PROJECT}"
# Wait a moment for the build pod to start
sleep 5
oc logs -f "bc/${APP_NAME}" -n "${DEMO_PROJECT}" || \
  oc logs -f "$(oc get pod -n "${DEMO_PROJECT}" -l build="${APP_NAME}" -o name | head -1)" \
    -n "${DEMO_PROJECT}" 2>/dev/null || \
  oc logs -f "$(oc get build "${APP_NAME}-1" -n "${DEMO_PROJECT}" -o name)" \
    -n "${DEMO_PROJECT}"

ok "Build complete!"
pause

# ── Step 4: Expose the service ────────────────────────────────────────────────
step "Exposing service as HTTPS Route..."
show_cmd "oc expose svc/${APP_NAME}
  -n ${DEMO_PROJECT}"
oc expose svc/"${APP_NAME}" -n "${DEMO_PROJECT}" 2>/dev/null || true
oc annotate route "${APP_NAME}" \
  haproxy.router.openshift.io/timeout=120s \
  -n "${DEMO_PROJECT}" --overwrite

# Get the route URL
ROUTE_URL=$(oc get route "${APP_NAME}" -n "${DEMO_PROJECT}" \
  -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

if [[ -z "${ROUTE_URL}" ]]; then
  warn "Route not found yet — waiting..."
  sleep 5
  ROUTE_URL=$(oc get route "${APP_NAME}" -n "${DEMO_PROJECT}" -o jsonpath='{.spec.host}')
fi

ok "Route is live!"
echo ""
echo -e "  ${BOLD}App URL  :${RESET} ${CYAN}http://${ROUTE_URL}/api/info${RESET}"
echo -e "  ${BOLD}Health   :${RESET} ${CYAN}http://${ROUTE_URL}/q/health${RESET}"
echo -e "  ${BOLD}Metrics  :${RESET} ${CYAN}http://${ROUTE_URL}/q/metrics${RESET}"
echo -e "  ${BOLD}Swagger  :${RESET} ${CYAN}http://${ROUTE_URL}/swagger-ui${RESET}"
echo ""

# ── Step 5: Verify the app responds ──────────────────────────────────────────
step "Verifying app response..."
wait_for_deployment "${APP_NAME}"

sleep 3
RESPONSE=$(curl -sf "http://${ROUTE_URL}/api/info" 2>/dev/null || echo "not ready yet")
echo -e "  Response: ${GREEN}${BOLD}${RESPONSE}${RESET}"
echo ""

ok "✅ From Git URL to Live App — done."
echo ""
echo -e "${BOLD}  Open in browser:${RESET}"
echo -e "    ${CYAN}http://${ROUTE_URL}/api/info${RESET}     ← shows hostname (pod name)"
echo -e "    ${CYAN}http://${ROUTE_URL}/swagger-ui${RESET}   ← explore all endpoints"
echo ""

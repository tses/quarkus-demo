#!/usr/bin/env bash
# =============================================================================
# 13-http-route.sh — ACT 4: attach an HTTPRoute so traffic flows to the app
# Idempotent: re-running re-applies the HTTPRoute and re-checks its status.
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/demo-config.sh"

header "ACT 4 — Expose Application with HTTPRoute"

check_login
use_project

# ── Step 1: Confirm the Gateway from step 12 is present and Programmed ───────
step "Confirming the Gateway '${GATEWAY_NAME}' is ready to attach routes to..."
show_cmd "oc get gateway ${GATEWAY_NAME} -n ${GATEWAY_NAMESPACE}"
if ! oc get gateway "${GATEWAY_NAME}" -n "${GATEWAY_NAMESPACE}" &>/dev/null; then
  warn "Gateway '${GATEWAY_NAME}' not found in '${GATEWAY_NAMESPACE}'."
  warn "Run scripts/12-gateway-api.sh first to create the Gateway."
  exit 1
fi
oc get gateway "${GATEWAY_NAME}" -n "${GATEWAY_NAMESPACE}" \
  -o custom-columns='NAME:.metadata.name,CLASS:.spec.gatewayClassName,ADDRESS:.status.addresses[0].value,PROGRAMMED:.status.conditions[?(@.type=="Programmed")].status'
echo ""
ok "Gateway is available"
echo ""
pause

# ── Step 2: Confirm the backend Service exists ───────────────────────────────
step "Confirming the backend Service '${APP_NAME}' exists..."
show_cmd "oc get svc ${APP_NAME} -n ${DEMO_PROJECT}"
if ! oc get svc "${APP_NAME}" -n "${DEMO_PROJECT}" &>/dev/null; then
  warn "Service '${APP_NAME}' not found in '${DEMO_PROJECT}'."
  warn "Deploy the application first (scripts/02-deploy-s2i.sh)."
  exit 1
fi
oc get svc "${APP_NAME}" -n "${DEMO_PROJECT}"
echo ""
ok "Backend Service is available on port 8080"
echo ""
pause

# ── Step 3: Determine the route hostname (must match the Gateway listener) ───
# Gateway API uses a dedicated subdomain (*.api.<cluster>), not the Route
# wildcard (*.apps.<cluster>).
GATEWAY_DOMAIN_RESOLVED="$(get_gateway_domain)"
if [[ -z "${GATEWAY_DOMAIN_RESOLVED}" ]]; then
  warn "Could not auto-detect the Gateway API domain."
  warn "Set GATEWAY_DOMAIN in demo-config.sh if needed."
  ROUTE_HOSTNAME="${APP_NAME}.example.com"
else
  ROUTE_HOSTNAME="${APP_NAME}.${GATEWAY_DOMAIN_RESOLVED}"
fi
echo -e "${YELLOW}  Route hostname: ${ROUTE_HOSTNAME}${RESET}"
echo -e "${YELLOW}  (matches the Gateway listener wildcard '*.${GATEWAY_DOMAIN_RESOLVED}')${RESET}"
echo ""

# ── Step 4: Create (or update) the HTTPRoute ─────────────────────────────────
step "Applying HTTPRoute '${APP_NAME}' attaching to Gateway '${GATEWAY_NAME}'..."
show_cmd "apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: ${APP_NAME}
  namespace: ${DEMO_PROJECT}
spec:
  parentRefs:
    - name: ${GATEWAY_NAME}
      namespace: ${GATEWAY_NAMESPACE}
  hostnames:
    - ${ROUTE_HOSTNAME}
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api
      backendRefs:
        - name: ${APP_NAME}
          port: 8080"
cat << EOF | oc apply -n "${DEMO_PROJECT}" -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: ${APP_NAME}
spec:
  parentRefs:
    - name: ${GATEWAY_NAME}
      namespace: ${GATEWAY_NAMESPACE}
  hostnames:
    - "${ROUTE_HOSTNAME}"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api
      backendRefs:
        - name: ${APP_NAME}
          port: 8080
EOF
echo ""
ok "HTTPRoute '${APP_NAME}' applied"
echo ""
pause

# ── Step 5: Verify the route was Accepted and resolved by the Gateway ────────
step "Checking the HTTPRoute parent (Gateway) status..."
show_cmd "oc get httproute ${APP_NAME} -n ${DEMO_PROJECT} \\
  -o jsonpath='{.status.parents[0].conditions}'"
echo ""
oc get httproute "${APP_NAME}" -n "${DEMO_PROJECT}" \
  -o jsonpath='{range .status.parents[0].conditions[*]}  {.type}={.status} ({.reason}){"\n"}{end}' 2>/dev/null || true
echo ""
step "HTTPRoute summary:"
oc get httproute "${APP_NAME}" -n "${DEMO_PROJECT}" \
  -o custom-columns='NAME:.metadata.name,HOSTNAMES:.spec.hostnames[*],GATEWAY:.spec.parentRefs[0].name'
echo ""
pause

# ── Step 6: Call the application THROUGH the Gateway ─────────────────────────
GW_ADDR="$(oc get gateway "${GATEWAY_NAME}" -n "${GATEWAY_NAMESPACE}" \
  -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)"

step "Calling the app through the Gateway (not the legacy Route)..."
if [[ -z "${GW_ADDR}" ]]; then
  warn "Gateway has no external address yet — skipping live curl."
else
  echo -e "  ${BOLD}Gateway address :${RESET} ${CYAN}${GW_ADDR}${RESET}"
  echo -e "  ${BOLD}Public URL      :${RESET} ${CYAN}http://${ROUTE_HOSTNAME}/api/info${RESET}"
  echo ""
  # Use --resolve so the request reaches the Gateway LB regardless of DNS.
  show_cmd "curl --resolve ${ROUTE_HOSTNAME}:80:${GW_ADDR} \\
  http://${ROUTE_HOSTNAME}/api/info"
  for i in 1 2 3; do
    RESP=$(curl -sf --resolve "${ROUTE_HOSTNAME}:80:${GW_ADDR}" \
      "http://${ROUTE_HOSTNAME}/api/info" 2>/dev/null || echo "no response")
    echo -e "  Request ${i}: ${GREEN}${RESP}${RESET}"
  done
fi
echo ""

echo -e "${YELLOW}  Traffic now flows: Client → Gateway → HTTPRoute → Service → Pods.${RESET}"
echo -e "${YELLOW}  Next (step 14): secure this entry point with a TLSPolicy.${RESET}"
echo ""
ok "ACT 4 — HTTPRoute exposure complete"

#!/usr/bin/env bash
# =============================================================================
# 15-auth-policy.sh — ACT 4: protect the exposed API with a Kuadrant AuthPolicy
# Requires API key authentication on the HTTPRoute from step 13.
# Idempotent: re-running re-applies the API key Secret, AuthPolicy and re-tests.
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/demo-config.sh"

header "ACT 4 — Protect API with AuthPolicy"

check_login
use_project

# ── Step 1: Confirm AuthPolicy (Kuadrant) prerequisites ──────────────────────
step "Confirming AuthPolicy (Kuadrant) is installed..."
show_cmd "oc get crd authpolicies.kuadrant.io"
if ! oc get crd authpolicies.kuadrant.io &>/dev/null; then
  warn "AuthPolicy CRD not found — install OpenShift Connectivity Link (Kuadrant)."
  exit 1
fi
ok "AuthPolicy CRD present"
echo ""
pause

# ── Step 2: Confirm the HTTPRoute from step 13 exists ────────────────────────
step "Confirming HTTPRoute '${APP_NAME}' exists to attach the policy to..."
show_cmd "oc get httproute ${APP_NAME} -n ${DEMO_PROJECT}"
if ! oc get httproute "${APP_NAME}" -n "${DEMO_PROJECT}" &>/dev/null; then
  warn "HTTPRoute '${APP_NAME}' not found — run scripts/13-http-route.sh first."
  exit 1
fi
oc get httproute "${APP_NAME}" -n "${DEMO_PROJECT}" \
  -o custom-columns='NAME:.metadata.name,HOSTNAMES:.spec.hostnames[*],GATEWAY:.spec.parentRefs[0].name'
echo ""
ok "HTTPRoute is available"
echo ""
pause

# ── Step 3: Resolve how to reach the app (scheme/port match steps 13/14) ─────
GW_ADDR="$(oc get gateway "${GATEWAY_NAME}" -n "${GATEWAY_NAMESPACE}" \
  -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)"
GATEWAY_DOMAIN_RESOLVED="$(get_gateway_domain)"
APP_HOST="${APP_NAME}.${GATEWAY_DOMAIN_RESOLVED}"

# Prefer the HTTPS listener added in step 14; fall back to HTTP from step 12.
if oc get gateway "${GATEWAY_NAME}" -n "${GATEWAY_NAMESPACE}" \
     -o jsonpath='{.spec.listeners[*].name}' 2>/dev/null | grep -qw https; then
  SCHEME="https"; PORT=443; CURL_TLS="-k"
else
  SCHEME="http"; PORT=80; CURL_TLS=""
fi
APP_URL="${SCHEME}://${APP_HOST}/api/info"

# Call the app through the Gateway and print ONLY the HTTP status code.
# $1 = optional value for the Authorization header (empty = no credentials).
call_status() {
  local auth="$1"
  if [[ -n "${auth}" ]]; then
    curl -s ${CURL_TLS} -o /dev/null -w '%{http_code}' \
      --resolve "${APP_HOST}:${PORT}:${GW_ADDR}" \
      -H "Authorization: ${auth}" "${APP_URL}" 2>/dev/null || echo "000"
  else
    curl -s ${CURL_TLS} -o /dev/null -w '%{http_code}' \
      --resolve "${APP_HOST}:${PORT}:${GW_ADDR}" "${APP_URL}" 2>/dev/null || echo "000"
  fi
}

# ── Step 4: Baseline — the API is currently open to anyone ───────────────────
step "Baseline: calling the API WITHOUT credentials (before the AuthPolicy)..."
if [[ -z "${GW_ADDR}" || -z "${GATEWAY_DOMAIN_RESOLVED}" ]]; then
  warn "Gateway address/domain unavailable — skipping live calls."
else
  echo -e "  ${BOLD}Public URL :${RESET} ${CYAN}${APP_URL}${RESET}"
  show_cmd "curl -i ${CURL_TLS} --resolve ${APP_HOST}:${PORT}:${GW_ADDR} \\
  ${APP_URL}"
  echo -e "  HTTP status (no key): ${GREEN}$(call_status "")${RESET}  ${YELLOW}(open until we enforce the policy)${RESET}"
fi
echo ""
pause

# ── Step 5: Create the API key Secret (consumed by Authorino) ────────────────
# Authorino reconciles Secrets labelled `authorino.kuadrant.io/managed-by:
# authorino`. The AuthPolicy selector (app=...) picks which of those are valid
# keys for this route. The key itself lives in `stringData.api_key`.
step "Creating the API key Secret '${AUTH_API_KEY_SECRET}' (label app=${AUTH_API_KEY_LABEL})..."
show_cmd "apiVersion: v1
kind: Secret
metadata:
  name: ${AUTH_API_KEY_SECRET}
  labels:
    authorino.kuadrant.io/managed-by: authorino
    app: ${AUTH_API_KEY_LABEL}
stringData:
  api_key: ${AUTH_API_KEY_VALUE}
type: Opaque"
cat << EOF | oc apply -n "${DEMO_PROJECT}" -f -
apiVersion: v1
kind: Secret
metadata:
  name: ${AUTH_API_KEY_SECRET}
  labels:
    authorino.kuadrant.io/managed-by: authorino
    app: ${AUTH_API_KEY_LABEL}
stringData:
  api_key: ${AUTH_API_KEY_VALUE}
type: Opaque
EOF
echo ""
ok "API key Secret created"
echo ""
pause

# ── Step 6: Apply the AuthPolicy targeting the HTTPRoute ─────────────────────
step "Applying AuthPolicy '${AUTH_POLICY_NAME}' requiring an API key on '${APP_NAME}'..."
show_cmd "apiVersion: kuadrant.io/v1
kind: AuthPolicy
metadata:
  name: ${AUTH_POLICY_NAME}
  namespace: ${DEMO_PROJECT}
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: ${APP_NAME}
  rules:
    authentication:
      api-key-users:
        apiKey:
          allNamespaces: true
          selector:
            matchLabels:
              app: ${AUTH_API_KEY_LABEL}
        credentials:
          authorizationHeader:
            prefix: ${AUTH_HEADER_PREFIX}"
cat << EOF | oc apply -n "${DEMO_PROJECT}" -f -
apiVersion: kuadrant.io/v1
kind: AuthPolicy
metadata:
  name: ${AUTH_POLICY_NAME}
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: ${APP_NAME}
  rules:
    authentication:
      "api-key-users":
        apiKey:
          allNamespaces: true
          selector:
            matchLabels:
              app: ${AUTH_API_KEY_LABEL}
        credentials:
          authorizationHeader:
            prefix: ${AUTH_HEADER_PREFIX}
EOF
echo ""
ok "AuthPolicy '${AUTH_POLICY_NAME}' applied"
echo ""

# ── Step 7: Wait for the AuthPolicy to be Accepted + Enforced ────────────────
step "Waiting for the AuthPolicy to be Accepted and Enforced..."
show_cmd "oc wait authpolicy/${AUTH_POLICY_NAME} -n ${DEMO_PROJECT} \\
  --for=condition=Enforced --timeout=60s"
if oc wait authpolicy/"${AUTH_POLICY_NAME}" -n "${DEMO_PROJECT}" \
     --for=condition=Enforced --timeout=60s 2>/dev/null; then
  ok "AuthPolicy is Enforced"
else
  warn "AuthPolicy not Enforced within timeout — inspect the conditions below"
fi
echo ""
step "AuthPolicy conditions:"
oc get authpolicy "${AUTH_POLICY_NAME}" -n "${DEMO_PROJECT}" \
  -o jsonpath='{range .status.conditions[*]}  {.type}={.status} ({.reason}){"\n"}{end}' 2>/dev/null || true
echo ""

# Give the Gateway's external authorization wiring a moment to take effect.
if [[ -n "${GW_ADDR}" && -n "${GATEWAY_DOMAIN_RESOLVED}" ]]; then
  step "Waiting for the Gateway to start rejecting unauthenticated calls..."
  for _ in $(seq 1 12); do
    [[ "$(call_status "")" == "401" ]] && break
    sleep 5
  done
fi
echo ""
pause

# ── Step 8: Verify — same API, with and without an API key ───────────────────
step "Verifying the policy: same API, with and without an API key..."
if [[ -z "${GW_ADDR}" || -z "${GATEWAY_DOMAIN_RESOLVED}" ]]; then
  warn "Gateway address/domain unavailable — skipping live calls."
else
  echo -e "  ${BOLD}Public URL :${RESET} ${CYAN}${APP_URL}${RESET}"
  echo ""

  show_cmd "# No credentials → expect 401 Unauthorized
curl -i ${CURL_TLS} --resolve ${APP_HOST}:${PORT}:${GW_ADDR} \\
  ${APP_URL}"
  echo -e "  No key        → HTTP ${RED}$(call_status "")${RESET}  (expected 401 Unauthorized)"
  echo ""

  show_cmd "# Valid API key → expect 200 OK
curl -i ${CURL_TLS} --resolve ${APP_HOST}:${PORT}:${GW_ADDR} \\
  -H 'Authorization: ${AUTH_HEADER_PREFIX} ${AUTH_API_KEY_VALUE}' \\
  ${APP_URL}"
  echo -e "  Valid API key → HTTP ${GREEN}$(call_status "${AUTH_HEADER_PREFIX} ${AUTH_API_KEY_VALUE}")${RESET}  (expected 200 OK)"
  echo ""

  echo -e "  Wrong API key → HTTP ${RED}$(call_status "${AUTH_HEADER_PREFIX} wrong-key")${RESET}  (expected 401 Unauthorized)"
fi
echo ""

echo -e "${YELLOW}  The API now requires a valid API key — authentication enforced at the Gateway.${RESET}"
echo -e "${YELLOW}  Next (step 16): add a RateLimitPolicy to throttle request volume.${RESET}"
echo ""
ok "ACT 4 — AuthPolicy complete"

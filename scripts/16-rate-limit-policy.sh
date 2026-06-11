#!/usr/bin/env bash
# =============================================================================
# 16-rate-limit-policy.sh — ACT 4: throttle the API with a RateLimitPolicy
# Caps requests per time window on the HTTPRoute from step 13.
# Idempotent: re-running re-applies the RateLimitPolicy and re-tests the limit.
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/demo-config.sh"

header "ACT 4 — Protect API with RateLimitPolicy"

check_login
use_project

# ── Step 1: Confirm RateLimitPolicy (Kuadrant) prerequisites ─────────────────
step "Confirming RateLimitPolicy (Kuadrant) is installed..."
show_cmd "oc get crd ratelimitpolicies.kuadrant.io"
if ! oc get crd ratelimitpolicies.kuadrant.io &>/dev/null; then
  warn "RateLimitPolicy CRD not found — install OpenShift Connectivity Link (Kuadrant)."
  exit 1
fi
ok "RateLimitPolicy CRD present"
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

# ── Step 3: Resolve how to reach the app (scheme/port/auth match steps 13-15) ─
GW_ADDR="$(oc get gateway "${GATEWAY_NAME}" -n "${GATEWAY_NAMESPACE}" \
  -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)"
GATEWAY_DOMAIN_RESOLVED="$(get_gateway_domain)"
APP_HOST="${APP_NAME}.${GATEWAY_DOMAIN_RESOLVED}"

# Prefer the HTTPS listener from step 14; fall back to HTTP from step 12.
if oc get gateway "${GATEWAY_NAME}" -n "${GATEWAY_NAMESPACE}" \
     -o jsonpath='{.spec.listeners[*].name}' 2>/dev/null | grep -qw https; then
  SCHEME="https"; PORT=443; CURL_TLS="-k"
else
  SCHEME="http"; PORT=80; CURL_TLS=""
fi
APP_URL="${SCHEME}://${APP_HOST}/api/info"

# If an AuthPolicy is enforced (step 15), calls must carry the API key.
AUTH_ARGS=()
if oc get authpolicy "${AUTH_POLICY_NAME}" -n "${DEMO_PROJECT}" &>/dev/null; then
  AUTH_ARGS=(-H "Authorization: ${AUTH_HEADER_PREFIX} ${AUTH_API_KEY_VALUE}")
  AUTH_NOTE="(authenticated with the step-15 API key)"
else
  AUTH_NOTE="(no AuthPolicy in place — calling unauthenticated)"
fi

# Call the app through the Gateway and print ONLY the HTTP status code.
call_status() {
  curl -s ${CURL_TLS} -o /dev/null -w '%{http_code}' \
    --resolve "${APP_HOST}:${PORT}:${GW_ADDR}" \
    "${AUTH_ARGS[@]}" "${APP_URL}" 2>/dev/null || echo "000"
}

# ── Step 4: Apply the RateLimitPolicy targeting the HTTPRoute ────────────────
step "Applying RateLimitPolicy '${RATE_LIMIT_POLICY_NAME}' — ${RATE_LIMIT} requests / ${RATE_WINDOW}..."
show_cmd "apiVersion: kuadrant.io/v1
kind: RateLimitPolicy
metadata:
  name: ${RATE_LIMIT_POLICY_NAME}
  namespace: ${DEMO_PROJECT}
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: ${APP_NAME}
  limits:
    demo-limit:
      rates:
        - limit: ${RATE_LIMIT}
          window: ${RATE_WINDOW}"
cat << EOF | oc apply -n "${DEMO_PROJECT}" -f -
apiVersion: kuadrant.io/v1
kind: RateLimitPolicy
metadata:
  name: ${RATE_LIMIT_POLICY_NAME}
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: ${APP_NAME}
  limits:
    "demo-limit":
      rates:
        - limit: ${RATE_LIMIT}
          window: ${RATE_WINDOW}
EOF
echo ""
ok "RateLimitPolicy '${RATE_LIMIT_POLICY_NAME}' applied"
echo ""

# ── Step 5: Wait for the RateLimitPolicy to be Accepted + Enforced ───────────
step "Waiting for the RateLimitPolicy to be Accepted and Enforced..."
show_cmd "oc wait ratelimitpolicy/${RATE_LIMIT_POLICY_NAME} -n ${DEMO_PROJECT} \\
  --for=condition=Enforced --timeout=60s"
if oc wait ratelimitpolicy/"${RATE_LIMIT_POLICY_NAME}" -n "${DEMO_PROJECT}" \
     --for=condition=Enforced --timeout=60s 2>/dev/null; then
  ok "RateLimitPolicy is Enforced"
else
  warn "RateLimitPolicy not Enforced within timeout — inspect the conditions below"
fi
echo ""
step "RateLimitPolicy conditions:"
oc get ratelimitpolicy "${RATE_LIMIT_POLICY_NAME}" -n "${DEMO_PROJECT}" \
  -o jsonpath='{range .status.conditions[*]}  {.type}={.status} ({.reason}){"\n"}{end}' 2>/dev/null || true
echo ""

# Give the Gateway's rate-limit wiring a moment to propagate to the data plane.
# NOTE: do NOT probe with live requests here — every call counts against the
# limit and would exhaust the window before the demo burst below.
if [[ -n "${GW_ADDR}" && -n "${GATEWAY_DOMAIN_RESOLVED}" ]]; then
  step "Giving the rate-limit configuration a few seconds to propagate..."
  sleep 5
fi
echo ""
pause

# ── Step 6: Demonstrate the limit — fire a burst and watch 200 → 429 ─────────
# Window length in seconds (RATE_WINDOW looks like "10s"); used to start from a
# fresh counter so the first requests are allowed before the limit kicks in.
WINDOW_SECS="${RATE_WINDOW%s}"
[[ "${WINDOW_SECS}" =~ ^[0-9]+$ ]] || WINDOW_SECS=10

step "Sending a burst of ${RATE_LIMIT_BURST} requests ${AUTH_NOTE}..."
if [[ -z "${GW_ADDR}" || -z "${GATEWAY_DOMAIN_RESOLVED}" ]]; then
  warn "Gateway address/domain unavailable — skipping live burst."
else
  echo -e "  ${BOLD}Public URL :${RESET} ${CYAN}${APP_URL}${RESET}"
  echo -e "  ${YELLOW}Limit: ${RATE_LIMIT} requests per ${RATE_WINDOW} → extra calls return 429${RESET}"
  echo ""
  # Wait out any in-flight window so the counter is fresh and the first
  # ${RATE_LIMIT} requests are allowed (200) before throttling (429) kicks in.
  step "Letting the current ${RATE_WINDOW} window reset before the burst..."
  sleep "$((WINDOW_SECS + 1))"
  echo ""
  show_cmd "for i in \$(seq 1 ${RATE_LIMIT_BURST}); do
  curl -s ${CURL_TLS} -o /dev/null -w '%{http_code}\\n' \\
    --resolve ${APP_HOST}:${PORT}:${GW_ADDR} \\
    -H 'Authorization: ${AUTH_HEADER_PREFIX} <api-key>' \\
    ${APP_URL}
done"
  allowed=0; limited=0
  for i in $(seq 1 "${RATE_LIMIT_BURST}"); do
    code="$(call_status)"
    if [[ "${code}" == "429" ]]; then
      limited=$((limited + 1))
      echo -e "  Request ${i}: HTTP ${RED}${code}${RESET}  (Too Many Requests — throttled)"
    else
      allowed=$((allowed + 1))
      echo -e "  Request ${i}: HTTP ${GREEN}${code}${RESET}"
    fi
  done
  echo ""
  echo -e "  ${BOLD}Allowed:${RESET} ${GREEN}${allowed}${RESET}   ${BOLD}Throttled (429):${RESET} ${RED}${limited}${RESET}"
fi
echo ""

echo -e "${YELLOW}  The API now rejects excess traffic — request volume capped at the Gateway.${RESET}"
echo -e "${YELLOW}  Next (step 17): advanced authorization with external metadata.${RESET}"
echo ""
ok "ACT 4 — RateLimitPolicy complete"

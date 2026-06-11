#!/usr/bin/env bash
# =============================================================================
# 17-external-metadata.sh — ACT 4: advanced authorization with external metadata
# Stands up a SECOND HTTPRoute on its own FQDN (same Gateway + backend) that:
#   • does NOT authenticate (anonymous) — trusts an X-Client-Id header that an
#     upstream WAF would set after mTLS;
#   • has Authorino fetch the caller's tier LIVE from an external metadata svc;
#   • applies a per-tier, per-client quota via a RateLimitPolicy.
# Idempotent: re-running re-applies the metadata svc, route and both policies.
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/demo-config.sh"

header "ACT 4 — Advanced Authorization with External Metadata"

check_login
use_project

# ── Step 1: Confirm prerequisites (CRDs + wildcard Gateway listener) ─────────
step "Confirming AuthPolicy/RateLimitPolicy CRDs and the Gateway are present..."
show_cmd "oc get crd authpolicies.kuadrant.io ratelimitpolicies.kuadrant.io
oc get gateway ${GATEWAY_NAME} -n ${GATEWAY_NAMESPACE}"
if ! oc get crd authpolicies.kuadrant.io ratelimitpolicies.kuadrant.io &>/dev/null; then
  warn "Kuadrant CRDs not found — install OpenShift Connectivity Link (Kuadrant)."
  exit 1
fi
if ! oc get gateway "${GATEWAY_NAME}" -n "${GATEWAY_NAMESPACE}" &>/dev/null; then
  warn "Gateway '${GATEWAY_NAME}' not found — run scripts/12-gateway-api.sh first."
  exit 1
fi
oc get gateway "${GATEWAY_NAME}" -n "${GATEWAY_NAMESPACE}" \
  -o jsonpath='{range .spec.listeners[*]}  listener={.name} host={.hostname} tls={.tls.mode}{"\n"}{end}' 2>/dev/null || true
ok "CRDs present and Gateway available"
echo ""
pause

# ── Step 2: Deploy the external metadata service ─────────────────────────────
# A tiny stdlib HTTP stub (no build, no registry): it reads the forwarded
# X-Client-Id header and returns the caller's tier AND the resolved identity.
# Unknown clients get tier "deny" and an empty id.
step "Deploying the external metadata service '${META_SVC_NAME}'..."
show_cmd "apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${META_SVC_NAME}
  labels: { app: ${META_SVC_NAME} }
spec:
  replicas: 1
  selector: { matchLabels: { app: ${META_SVC_NAME} } }
  template:
    spec:
      containers:
        - name: svc
          image: registry.access.redhat.com/ubi9/python-312:latest
          command: [\"python\", \"-c\"]
          args: [ <inline http server: returns {\"tier\":..., \"id\":...}> ]
---
apiVersion: v1
kind: Service
metadata: { name: ${META_SVC_NAME} }
spec:
  selector: { app: ${META_SVC_NAME} }
  ports: [{ port: ${META_SVC_PORT}, targetPort: ${META_SVC_PORT} }]"
cat << EOF | oc apply -n "${DEMO_PROJECT}" -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${META_SVC_NAME}
  labels:
    app: ${META_SVC_NAME}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${META_SVC_NAME}
  template:
    metadata:
      labels:
        app: ${META_SVC_NAME}
    spec:
      containers:
        - name: svc
          image: registry.access.redhat.com/ubi9/python-312:latest
          ports:
            - containerPort: ${META_SVC_PORT}
          readinessProbe:
            tcpSocket:
              port: ${META_SVC_PORT}
            initialDelaySeconds: 3
            periodSeconds: 5
          command: ["python", "-c"]
          args:
            - |
              import json
              from http.server import BaseHTTPRequestHandler, HTTPServer
              # The live "source of truth": which client maps to which tier.
              TIERS = {"${MTLS_GOLD_CLIENT}": "gold", "${MTLS_SILVER_CLIENT}": "silver"}
              class H(BaseHTTPRequestHandler):
                  def do_GET(self):
                      client = self.headers.get("${MTLS_CLIENT_HEADER}", "")
                      tier = TIERS.get(client, "deny")
                      # Return the resolved identity too, so policies count on
                      # what the metadata service validated — not the raw header.
                      cid = client if tier != "deny" else ""
                      body = json.dumps({"tier": tier, "id": cid}).encode()
                      self.send_response(200)
                      self.send_header("Content-Type", "application/json")
                      self.send_header("Content-Length", str(len(body)))
                      self.end_headers()
                      self.wfile.write(body)
                  def log_message(self, *a):
                      pass
              HTTPServer(("0.0.0.0", ${META_SVC_PORT}), H).serve_forever()
---
apiVersion: v1
kind: Service
metadata:
  name: ${META_SVC_NAME}
  labels:
    app: ${META_SVC_NAME}
spec:
  selector:
    app: ${META_SVC_NAME}
  ports:
    - port: ${META_SVC_PORT}
      targetPort: ${META_SVC_PORT}
EOF
echo ""
wait_for_deployment "${META_SVC_NAME}"
echo ""
pause

# ── Step 3: Determine the new route hostname (own FQDN, same wildcard) ────────
GATEWAY_DOMAIN_RESOLVED="$(get_gateway_domain)"
if [[ -z "${GATEWAY_DOMAIN_RESOLVED}" ]]; then
  warn "Could not auto-detect the Gateway API domain. Set GATEWAY_DOMAIN in demo-config.sh."
  MTLS_HOST="${MTLS_ROUTE_NAME}.example.com"
else
  MTLS_HOST="${MTLS_ROUTE_NAME}.${GATEWAY_DOMAIN_RESOLVED}"
fi
echo -e "${YELLOW}  New route hostname: ${MTLS_HOST}${RESET}"
echo -e "${YELLOW}  (covered by the Gateway wildcard '*.${GATEWAY_DOMAIN_RESOLVED}')${RESET}"
echo ""

# ── Step 4: Create the second HTTPRoute (new FQDN, same backend Service) ─────
step "Applying HTTPRoute '${MTLS_ROUTE_NAME}' on its own FQDN..."
show_cmd "apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: ${MTLS_ROUTE_NAME}
  namespace: ${DEMO_PROJECT}
spec:
  parentRefs:
    - name: ${GATEWAY_NAME}
      namespace: ${GATEWAY_NAMESPACE}
  hostnames:
    - ${MTLS_HOST}
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api
      backendRefs:
        - name: ${APP_NAME}        # SAME backend as the step-13 route
          port: 8080"
cat << EOF | oc apply -n "${DEMO_PROJECT}" -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: ${MTLS_ROUTE_NAME}
spec:
  parentRefs:
    - name: ${GATEWAY_NAME}
      namespace: ${GATEWAY_NAMESPACE}
  hostnames:
    - "${MTLS_HOST}"
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
ok "HTTPRoute '${MTLS_ROUTE_NAME}' applied"
echo ""
pause

# ── Step 5: AuthPolicy — anonymous + external metadata lookup ────────────────
# No credential check (anonymous): the WAF already did mTLS upstream and
# forwarded the identity in the X-Client-Id header. Authorino fetches the
# caller's tier from the metadata service and denies unknown clients (403).
# ── Step 5: AuthPolicy — anonymous + external metadata lookup ────────────────
# No credential check (anonymous): the WAF already did mTLS upstream and
# forwarded the identity in the X-Client-Id header. Authorino fetches the
# caller's tier from the metadata service and denies unknown clients (403).
# It also EXPORTS the tier + identity as dynamic metadata via
# response.success.filters so the RateLimitPolicy below can read them — the
# rate-limit phase cannot see auth.metadata.* directly, only what auth exports.
step "Applying AuthPolicy '${MTLS_AUTH_POLICY_NAME}' (anonymous + metadata + export)..."
show_cmd "apiVersion: kuadrant.io/v1
kind: AuthPolicy
metadata:
  name: ${MTLS_AUTH_POLICY_NAME}
  namespace: ${DEMO_PROJECT}
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: ${MTLS_ROUTE_NAME}
  rules:
    authentication:
      anonymous:
        anonymous: {}
    metadata:
      caller_info:
        http:
          url: http://${META_SVC_NAME}.${DEMO_PROJECT}.svc.cluster.local:${META_SVC_PORT}/lookup
          method: GET
          headers:
            ${MTLS_CLIENT_HEADER}:
              selector: request.headers.x-client-id
    authorization:
      known-clients-only:
        patternMatching:
          patterns:
            - selector: auth.metadata.caller_info.tier
              operator: neq
              value: deny
    response:
      success:
        filters:
          identity:                       # exported as auth.identity.* downstream
            json:
              properties:
                tier:
                  selector: auth.metadata.caller_info.tier
                userid:
                  selector: auth.metadata.caller_info.id"
cat << EOF | oc apply -n "${DEMO_PROJECT}" -f -
apiVersion: kuadrant.io/v1
kind: AuthPolicy
metadata:
  name: ${MTLS_AUTH_POLICY_NAME}
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: ${MTLS_ROUTE_NAME}
  rules:
    authentication:
      "anonymous":
        anonymous: {}
    metadata:
      "caller_info":
        http:
          url: "http://${META_SVC_NAME}.${DEMO_PROJECT}.svc.cluster.local:${META_SVC_PORT}/lookup"
          method: GET
          headers:
            "${MTLS_CLIENT_HEADER}":
              selector: "request.headers.x-client-id"
    authorization:
      "known-clients-only":
        patternMatching:
          patterns:
            - selector: "auth.metadata.caller_info.tier"
              operator: neq
              value: deny
    response:
      success:
        filters:
          "identity":
            json:
              properties:
                "tier":
                  selector: auth.metadata.caller_info.tier
                "userid":
                  selector: auth.metadata.caller_info.id
EOF
echo ""
ok "AuthPolicy '${MTLS_AUTH_POLICY_NAME}' applied"
echo ""

# ── Step 6: RateLimitPolicy — per-tier, per-client quota ─────────────────────
# `when` selects the limit by the tier EXPORTED by the AuthPolicy (auth.identity.tier);
# `counters` keys the budget on the exported identity (auth.identity.userid), so
# each client gets an independent quota. Note: the rate-limit phase reads the
# auth result via auth.identity.*, NOT auth.metadata.* (which is internal to auth).
step "Applying RateLimitPolicy '${MTLS_RL_POLICY_NAME}' (gold ${MTLS_GOLD_LIMIT}/${MTLS_TIER_WINDOW}, silver ${MTLS_SILVER_LIMIT}/${MTLS_TIER_WINDOW})..."
show_cmd "apiVersion: kuadrant.io/v1
kind: RateLimitPolicy
metadata:
  name: ${MTLS_RL_POLICY_NAME}
  namespace: ${DEMO_PROJECT}
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: ${MTLS_ROUTE_NAME}
  limits:
    gold:
      rates: [{ limit: ${MTLS_GOLD_LIMIT}, window: ${MTLS_TIER_WINDOW} }]
      when:     [{ predicate: 'auth.identity.tier == \"gold\"' }]
      counters: [{ expression: 'auth.identity.userid' }]
    silver:
      rates: [{ limit: ${MTLS_SILVER_LIMIT}, window: ${MTLS_TIER_WINDOW} }]
      when:     [{ predicate: 'auth.identity.tier == \"silver\"' }]
      counters: [{ expression: 'auth.identity.userid' }]"
cat << EOF | oc apply -n "${DEMO_PROJECT}" -f -
apiVersion: kuadrant.io/v1
kind: RateLimitPolicy
metadata:
  name: ${MTLS_RL_POLICY_NAME}
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: ${MTLS_ROUTE_NAME}
  limits:
    "gold":
      rates:
        - limit: ${MTLS_GOLD_LIMIT}
          window: ${MTLS_TIER_WINDOW}
      when:
        - predicate: 'auth.identity.tier == "gold"'
      counters:
        - expression: 'auth.identity.userid'
    "silver":
      rates:
        - limit: ${MTLS_SILVER_LIMIT}
          window: ${MTLS_TIER_WINDOW}
      when:
        - predicate: 'auth.identity.tier == "silver"'
      counters:
        - expression: 'auth.identity.userid'
EOF
echo ""
ok "RateLimitPolicy '${MTLS_RL_POLICY_NAME}' applied"
echo ""

# ── Step 7: Wait for both policies to be Enforced ────────────────────────────
step "Waiting for the AuthPolicy and RateLimitPolicy to be Enforced..."
show_cmd "oc wait authpolicy/${MTLS_AUTH_POLICY_NAME}    -n ${DEMO_PROJECT} --for=condition=Enforced --timeout=60s
oc wait ratelimitpolicy/${MTLS_RL_POLICY_NAME} -n ${DEMO_PROJECT} --for=condition=Enforced --timeout=60s"
oc wait authpolicy/"${MTLS_AUTH_POLICY_NAME}" -n "${DEMO_PROJECT}" \
  --for=condition=Enforced --timeout=60s 2>/dev/null \
  && ok "AuthPolicy is Enforced" \
  || warn "AuthPolicy not Enforced within timeout — check conditions"
oc wait ratelimitpolicy/"${MTLS_RL_POLICY_NAME}" -n "${DEMO_PROJECT}" \
  --for=condition=Enforced --timeout=60s 2>/dev/null \
  && ok "RateLimitPolicy is Enforced" \
  || warn "RateLimitPolicy not Enforced within timeout — check conditions"
echo ""

# ── Step 8: Resolve how to reach the route (scheme/port from the Gateway) ────
GW_ADDR="$(oc get gateway "${GATEWAY_NAME}" -n "${GATEWAY_NAMESPACE}" \
  -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)"
if oc get gateway "${GATEWAY_NAME}" -n "${GATEWAY_NAMESPACE}" \
     -o jsonpath='{.spec.listeners[*].name}' 2>/dev/null | grep -qw https; then
  SCHEME="https"; PORT=443; CURL_TLS="-k"
else
  SCHEME="http"; PORT=80; CURL_TLS=""
fi
MTLS_URL="${SCHEME}://${MTLS_HOST}/api/info"

# Call the route as a given client id (no API key — identity is just a header).
call_status() { # $1 = client id value for the X-Client-Id header
  curl -s ${CURL_TLS} -o /dev/null -w '%{http_code}' \
    --resolve "${MTLS_HOST}:${PORT}:${GW_ADDR}" \
    -H "${MTLS_CLIENT_HEADER}: $1" "${MTLS_URL}" 2>/dev/null || echo "000"
}

# Fire a burst as one client and summarise allowed vs throttled.
run_burst() { # $1 = client id, $2 = tier label, $3 = expected limit
  local client="$1" tier="$2" limit="$3" allowed=0 limited=0 code
  step "Client '${client}' (${tier}, limit ${limit}/${MTLS_TIER_WINDOW}) — burst of ${MTLS_BURST}..."
  for i in $(seq 1 "${MTLS_BURST}"); do
    code="$(call_status "${client}")"
    if [[ "${code}" == "429" ]]; then
      limited=$((limited + 1))
      echo -e "  Request ${i}: HTTP ${RED}${code}${RESET}  (throttled)"
    else
      allowed=$((allowed + 1))
      echo -e "  Request ${i}: HTTP ${GREEN}${code}${RESET}"
    fi
  done
  echo -e "  ${BOLD}Allowed:${RESET} ${GREEN}${allowed}${RESET}   ${BOLD}Throttled (429):${RESET} ${RED}${limited}${RESET}"
  echo ""
}

step "Demonstrating tier-based authorization & rate limiting (identity via header only)..."
if [[ -z "${GW_ADDR}" || -z "${GATEWAY_DOMAIN_RESOLVED}" ]]; then
  warn "Gateway address/domain unavailable — skipping live calls."
else
  echo -e "  ${BOLD}Public URL :${RESET} ${CYAN}${MTLS_URL}${RESET}"
  echo ""
  # Let the Gateway's auth/rate-limit wiring settle.
  step "Letting the policy wiring propagate to the data plane..."
  for s in $(seq 8 -1 1); do
    printf '\r  Settling… %ds ' "${s}"
    sleep 1
  done
  printf '\r%*s\r' 30 ''   # clear the countdown line
  echo ""

  show_cmd "# Identity is just a header — no API key on this route
for i in \$(seq 1 ${MTLS_BURST}); do
  curl -s ${CURL_TLS} -o /dev/null -w '%{http_code}\\n' \\
    --resolve ${MTLS_HOST}:${PORT}:${GW_ADDR} \\
    -H '${MTLS_CLIENT_HEADER}: ${MTLS_GOLD_CLIENT}' \\
    ${MTLS_URL}
done"
  run_burst "${MTLS_GOLD_CLIENT}"   "gold"   "${MTLS_GOLD_LIMIT}"
  run_burst "${MTLS_SILVER_CLIENT}" "silver" "${MTLS_SILVER_LIMIT}"

  step "Unknown client '${MTLS_UNKNOWN_CLIENT}' — rejected at authorization..."
  show_cmd "curl -s ${CURL_TLS} -o /dev/null -w '%{http_code}\\n' \\
  --resolve ${MTLS_HOST}:${PORT}:${GW_ADDR} \\
  -H '${MTLS_CLIENT_HEADER}: ${MTLS_UNKNOWN_CLIENT}' \\
  ${MTLS_URL}"
  code="$(call_status "${MTLS_UNKNOWN_CLIENT}")"
  echo -e "  Unknown client: HTTP ${RED}${code}${RESET}  (expected 403 — not in the tier map)"
fi
echo ""

echo -e "${YELLOW}  Authorization & quota are now computed LIVE from external metadata.${RESET}"
echo -e "${YELLOW}  Change what '${META_SVC_NAME}' returns → behaviour changes, no policy edit.${RESET}"
echo -e "${YELLOW}  Next (step 18): observe this protected API traffic end-to-end.${RESET}"
echo ""
ok "ACT 4 — External metadata authorization complete"

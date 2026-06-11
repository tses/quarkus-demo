#!/usr/bin/env bash
# =============================================================================
# 14-tls-policy.sh — ACT 4: secure the Gateway with a Kuadrant TLSPolicy
# Adds an HTTPS listener and lets cert-manager provision its certificate.
# Idempotent: re-running re-applies the listener, TLSPolicy and re-checks status.
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/demo-config.sh"

header "ACT 4 — Secure Traffic with TLSPolicy"

check_login
use_project

# ── Step 1: Confirm TLSPolicy + cert-manager prerequisites ───────────────────
step "Confirming TLSPolicy (Kuadrant) and cert-manager are installed..."
show_cmd "oc get crd tlspolicies.kuadrant.io certificates.cert-manager.io"
if ! oc get crd tlspolicies.kuadrant.io &>/dev/null; then
  warn "TLSPolicy CRD not found — install OpenShift Connectivity Link (Kuadrant)."
  exit 1
fi
if ! oc get crd certificates.cert-manager.io &>/dev/null; then
  warn "cert-manager CRDs not found — TLSPolicy needs cert-manager to issue certs."
  exit 1
fi
ok "TLSPolicy + cert-manager CRDs present"
echo ""

step "Confirming issuer '${GATEWAY_TLS_ISSUER}' (${GATEWAY_TLS_ISSUER_KIND}) is Ready..."
if [[ "${GATEWAY_TLS_ISSUER_KIND}" == "ClusterIssuer" ]]; then
  show_cmd "oc get clusterissuer ${GATEWAY_TLS_ISSUER}"
  if ! oc get clusterissuer "${GATEWAY_TLS_ISSUER}" &>/dev/null; then
    warn "ClusterIssuer '${GATEWAY_TLS_ISSUER}' not found."
    warn "Set GATEWAY_TLS_ISSUER / GATEWAY_TLS_ISSUER_KIND in demo-config.sh."
    exit 1
  fi
  oc get clusterissuer "${GATEWAY_TLS_ISSUER}"
else
  show_cmd "oc get issuer ${GATEWAY_TLS_ISSUER} -n ${DEMO_PROJECT}"
  if ! oc get issuer "${GATEWAY_TLS_ISSUER}" -n "${DEMO_PROJECT}" &>/dev/null; then
    warn "Issuer '${GATEWAY_TLS_ISSUER}' not found in '${DEMO_PROJECT}'."
    exit 1
  fi
  oc get issuer "${GATEWAY_TLS_ISSUER}" -n "${DEMO_PROJECT}"
fi
ok "Issuer is available"
echo ""
pause

# ── Step 2: Confirm the Gateway from step 12 exists ──────────────────────────
step "Confirming Gateway '${GATEWAY_NAME}' exists..."
show_cmd "oc get gateway ${GATEWAY_NAME} -n ${GATEWAY_NAMESPACE}"
if ! oc get gateway "${GATEWAY_NAME}" -n "${GATEWAY_NAMESPACE}" &>/dev/null; then
  warn "Gateway '${GATEWAY_NAME}' not found — run scripts/12-gateway-api.sh first."
  exit 1
fi
oc get gateway "${GATEWAY_NAME}" -n "${GATEWAY_NAMESPACE}"
echo ""
ok "Gateway is available"
echo ""
pause

# ── Step 3: Resolve the Gateway API domain (matches step 12/13) ──────────────
GATEWAY_DOMAIN_RESOLVED="$(get_gateway_domain)"
if [[ -z "${GATEWAY_DOMAIN_RESOLVED}" ]]; then
  warn "Could not auto-detect the Gateway API domain — using wildcard '*'."
  LISTENER_HOSTNAME="*"
else
  LISTENER_HOSTNAME="*.${GATEWAY_DOMAIN_RESOLVED}"
fi
echo -e "${YELLOW}  HTTPS listener hostname: ${LISTENER_HOSTNAME}${RESET}"
echo ""

# ── Step 4: Add an HTTPS listener to the Gateway ─────────────────────────────
# Re-apply the Gateway with BOTH listeners (http :80 + https :443). The HTTPS
# listener terminates TLS using a Secret that cert-manager will populate.
step "Adding an HTTPS listener (:443) to the Gateway, terminating into '${GATEWAY_TLS_SECRET}'..."
show_cmd "listeners:
  - name: http       # existing
      protocol: HTTP
      port: 80
  - name: https      # NEW
      protocol: HTTPS
      port: 443
      hostname: ${LISTENER_HOSTNAME}
      tls:
        mode: Terminate
        certificateRefs:
          - kind: Secret
            name: ${GATEWAY_TLS_SECRET}"
cat << EOF | oc apply -n "${GATEWAY_NAMESPACE}" -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: ${GATEWAY_NAME}
spec:
  gatewayClassName: ${GATEWAY_CLASS}
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      hostname: "${LISTENER_HOSTNAME}"
      allowedRoutes:
        namespaces:
          from: Same
    - name: https
      protocol: HTTPS
      port: 443
      hostname: "${LISTENER_HOSTNAME}"
      tls:
        mode: Terminate
        certificateRefs:
          - kind: Secret
            name: ${GATEWAY_TLS_SECRET}
      allowedRoutes:
        namespaces:
          from: Same
EOF
echo ""
ok "HTTPS listener added"
echo ""
pause

# ── Step 5: Apply the TLSPolicy targeting the Gateway ────────────────────────
step "Applying TLSPolicy '${GATEWAY_TLS_POLICY_NAME}' targeting the Gateway..."
show_cmd "apiVersion: kuadrant.io/v1
kind: TLSPolicy
metadata:
  name: ${GATEWAY_TLS_POLICY_NAME}
  namespace: ${DEMO_PROJECT}
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: Gateway
    name: ${GATEWAY_NAME}
  issuerRef:
    group: cert-manager.io
    kind: ${GATEWAY_TLS_ISSUER_KIND}
    name: ${GATEWAY_TLS_ISSUER}"
cat << EOF | oc apply -n "${DEMO_PROJECT}" -f -
apiVersion: kuadrant.io/v1
kind: TLSPolicy
metadata:
  name: ${GATEWAY_TLS_POLICY_NAME}
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: Gateway
    name: ${GATEWAY_NAME}
  issuerRef:
    group: cert-manager.io
    kind: ${GATEWAY_TLS_ISSUER_KIND}
    name: ${GATEWAY_TLS_ISSUER}
EOF
echo ""
ok "TLSPolicy '${GATEWAY_TLS_POLICY_NAME}' applied"
echo ""

# ── Step 6: Wait for cert-manager to issue the certificate ───────────────────
step "Waiting for cert-manager to issue the certificate into Secret '${GATEWAY_TLS_SECRET}'..."
show_cmd "oc get certificate -n ${DEMO_PROJECT}
oc wait --for=condition=Ready certificate -n ${DEMO_PROJECT} --all --timeout=120s"
if oc wait --for=condition=Ready certificate -n "${DEMO_PROJECT}" --all --timeout=120s 2>/dev/null; then
  ok "Certificate is Ready"
else
  warn "Certificate not Ready within timeout — inspect status below"
fi
echo ""
oc get certificate -n "${DEMO_PROJECT}" 2>/dev/null || true
echo ""

step "Waiting for the secret '${GATEWAY_TLS_SECRET}' to be populated..."
for _ in $(seq 1 24); do
  if oc get secret "${GATEWAY_TLS_SECRET}" -n "${DEMO_PROJECT}" &>/dev/null; then
    ok "TLS secret '${GATEWAY_TLS_SECRET}' exists"
    break
  fi
  sleep 5
done
echo ""

# ── Step 7: Show TLSPolicy + Gateway status ──────────────────────────────────
step "TLSPolicy conditions:"
oc get tlspolicy "${GATEWAY_TLS_POLICY_NAME}" -n "${DEMO_PROJECT}" \
  -o jsonpath='{range .status.conditions[*]}  {.type}={.status} ({.reason}){"\n"}{end}' 2>/dev/null || true
echo ""
step "Gateway HTTPS listener status:"
oc get gateway "${GATEWAY_NAME}" -n "${GATEWAY_NAMESPACE}" \
  -o jsonpath='{range .status.listeners[*]}  {.name}: programmed={range .conditions[?(@.type=="Programmed")]}{.status}{end}{"\n"}{end}' 2>/dev/null || true
echo ""
pause

# ── Step 8: Verify HTTPS through the Gateway ─────────────────────────────────
GW_ADDR="$(oc get gateway "${GATEWAY_NAME}" -n "${GATEWAY_NAMESPACE}" \
  -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)"
HTTPS_HOST="${APP_NAME}.${GATEWAY_DOMAIN_RESOLVED}"

step "Calling the app over HTTPS through the Gateway..."
if [[ -z "${GW_ADDR}" || -z "${GATEWAY_DOMAIN_RESOLVED}" ]]; then
  warn "Gateway address or domain unavailable — skipping live HTTPS test."
else
  echo -e "  ${BOLD}Public URL :${RESET} ${CYAN}https://${HTTPS_HOST}/api/info${RESET}"
  echo -e "  ${YELLOW}(-k accepts the self-signed cert; production uses a trusted CA)${RESET}"
  echo ""
  show_cmd "curl -sk --resolve ${HTTPS_HOST}:443:${GW_ADDR} \\
  https://${HTTPS_HOST}/api/info"
  for i in 1 2 3; do
    RESP=$(curl -sk --resolve "${HTTPS_HOST}:443:${GW_ADDR}" \
      "https://${HTTPS_HOST}/api/info" 2>/dev/null || echo "no response")
    echo -e "  Request ${i}: ${GREEN}${RESP}${RESET}"
  done
fi
echo ""

echo -e "${YELLOW}  TLS is now terminated at the Gateway — certificate managed by cert-manager.${RESET}"
echo -e "${YELLOW}  Next (step 15): protect the API with an AuthPolicy.${RESET}"
echo ""
ok "ACT 4 — TLSPolicy complete"

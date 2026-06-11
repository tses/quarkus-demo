#!/usr/bin/env bash
# =============================================================================
# 12-gateway-api.sh — ACT 4 intro: confirm Gateway API + create a Gateway
# Idempotent: re-running re-applies the Gateway and re-checks status.
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/demo-config.sh"

header "ACT 4 — Gateway API Introduction"

check_login
use_project

# ── Step 1: Confirm Gateway API CRDs are present ─────────────────────────────
step "Confirming Gateway API is installed (Connectivity Link / Kuadrant)..."
show_cmd "oc get crd | grep gateway.networking.k8s.io"
# Query the CRD by name directly (no pipe). Using `oc get crd | grep -q ...`
# is unsafe under `set -o pipefail`: grep -q exits on the first match and
# closes the pipe, oc then dies with SIGPIPE (exit 141), and pipefail makes
# the whole pipeline report failure — a false "not installed" result.
if ! oc get crd gateways.gateway.networking.k8s.io &>/dev/null; then
  warn "Gateway API CRDs not found."
  warn "Install OpenShift Connectivity Link (Kuadrant) before running ACT 4."
  exit 1
fi
oc get crd 2>/dev/null | grep "gateway.networking.k8s.io" || true
ok "Gateway API CRDs present"
echo ""
pause

# ── Step 2: Inspect the GatewayClass ─────────────────────────────────────────
step "Listing available GatewayClasses..."
show_cmd "oc get gatewayclass"
oc get gatewayclass 2>/dev/null || true
echo ""
if ! oc get gatewayclass "${GATEWAY_CLASS}" &>/dev/null; then
  warn "GatewayClass '${GATEWAY_CLASS}' not found — check Connectivity Link install."
  warn "Set GATEWAY_CLASS in demo-config.sh to a class shown above if it differs."
  exit 1
fi
ok "Using GatewayClass: ${GATEWAY_CLASS}"
echo ""
pause

# ── Step 3: Determine the Gateway API domain for the listener hostname ───────
# Gateway API uses a dedicated subdomain (e.g. *.api.<cluster>), separate from
# the default Router/Route wildcard (*.apps.<cluster>).
GATEWAY_DOMAIN_RESOLVED="$(get_gateway_domain)"
if [[ -z "${GATEWAY_DOMAIN_RESOLVED}" ]]; then
  warn "Could not auto-detect the Gateway API domain."
  warn "Falling back to wildcard '*' listener hostname."
  LISTENER_HOSTNAME="*"
else
  LISTENER_HOSTNAME="*.${GATEWAY_DOMAIN_RESOLVED}"
fi
echo -e "${YELLOW}  Listener hostname: ${LISTENER_HOSTNAME}${RESET}"
echo ""

# ── Step 4: Create (or update) the Gateway ───────────────────────────────────
step "Applying Gateway '${GATEWAY_NAME}' in namespace '${GATEWAY_NAMESPACE}'..."
show_cmd "apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: ${GATEWAY_NAME}
  namespace: ${GATEWAY_NAMESPACE}
spec:
  gatewayClassName: ${GATEWAY_CLASS}
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      hostname: ${LISTENER_HOSTNAME}
      allowedRoutes:
        namespaces:
          from: Same"
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
EOF
echo ""
ok "Gateway '${GATEWAY_NAME}' applied"
echo ""

# ── Step 5: Wait for the Gateway to be Programmed ────────────────────────────
step "Waiting for the controller to program the Gateway (provision data-plane)..."
show_cmd "oc wait gateway/${GATEWAY_NAME} -n ${GATEWAY_NAMESPACE} --for=condition=Programmed --timeout=120s"
if oc wait gateway/"${GATEWAY_NAME}" -n "${GATEWAY_NAMESPACE}" \
     --for=condition=Programmed --timeout=120s 2>/dev/null; then
  ok "Gateway is Programmed — entry point is live"
else
  warn "Gateway not Programmed within timeout — inspect status below"
fi
echo ""

# ── Step 6: Show the Gateway status / address ────────────────────────────────
step "Gateway summary:"
echo ""
oc get gateway "${GATEWAY_NAME}" -n "${GATEWAY_NAMESPACE}" \
  -o custom-columns='NAME:.metadata.name,CLASS:.spec.gatewayClassName,ADDRESS:.status.addresses[0].value,PROGRAMMED:.status.conditions[?(@.type=="Programmed")].status'
echo ""
step "Key conditions:"
oc get gateway "${GATEWAY_NAME}" -n "${GATEWAY_NAMESPACE}" \
  -o jsonpath='{range .status.conditions[*]}  {.type}={.status} ({.reason}){"\n"}{end}' 2>/dev/null || true
echo ""

echo -e "${YELLOW}  The Gateway opens the door, but routes nothing yet.${RESET}"
echo -e "${YELLOW}  Next (step 13): attach an HTTPRoute to send traffic to ${APP_NAME}.${RESET}"
echo ""
ok "ACT 4 — Gateway API introduction complete"

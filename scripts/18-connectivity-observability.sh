#!/usr/bin/env bash
# =============================================================================
# 18-connectivity-observability.sh — ACT 4: observe API connectivity
# Connectivity Link plugs into the cluster's user-workload monitoring; the
# Grafana dashboards (and istio_requests_total) only populate once traffic
# flows through the Gateway. This step:
#   • confirms observability is enabled on the Kuadrant CR + monitors exist;
#   • points at the Grafana / Console "Observe" entry points;
#   • drives a steady stream of traffic across the step-13/16 route and the
#     step-17 per-tier route so request-rate / error-rate / 429 panels fill in.
# Idempotent: it only reads cluster state and sends traffic — re-run any time
# to keep the dashboards busy.
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/demo-config.sh"

header "ACT 4 — Observe API Connectivity"

check_login
use_project

# ── Step 1: Confirm observability is enabled on the Kuadrant CR ──────────────
step "Confirming observability is enabled on the Kuadrant CR..."
show_cmd "oc get kuadrant ${OBS_KUADRANT_NAME} -n ${OBS_KUADRANT_NS} \\
  -o jsonpath='{.spec.observability.enable}'"
if oc get kuadrant "${OBS_KUADRANT_NAME}" -n "${OBS_KUADRANT_NS}" &>/dev/null; then
  OBS_ENABLED="$(oc get kuadrant "${OBS_KUADRANT_NAME}" -n "${OBS_KUADRANT_NS}" \
    -o jsonpath='{.spec.observability.enable}' 2>/dev/null || true)"
  if [[ "${OBS_ENABLED}" == "true" ]]; then
    ok "spec.observability.enable = true"
  else
    warn "Observability not enabled. Turn it on with:"
    echo -e "  ${CYAN}oc -n ${OBS_KUADRANT_NS} patch kuadrant ${OBS_KUADRANT_NAME} --type merge \\\\
    -p '{\"spec\":{\"observability\":{\"enable\":true}}}'${RESET}"
    echo -e "  ${YELLOW}See observability/how-to-setup-monitor.md for the full setup.${RESET}"
  fi
else
  warn "Kuadrant CR '${OBS_KUADRANT_NAME}' not found in '${OBS_KUADRANT_NS}' — is Connectivity Link installed?"
fi
echo ""
pause

# ── Step 2: Show the monitors CL created when observability was enabled ──────
step "Listing the Service/PodMonitors Connectivity Link manages..."
show_cmd "oc get servicemonitor,podmonitor -A -l kuadrant.io/observability=true"
oc get servicemonitor,podmonitor -A -l kuadrant.io/observability=true 2>/dev/null \
  || warn "No CL-managed monitors found yet (they appear once observability is enabled)."
echo ""
ok "These monitors tell OpenShift's Prometheus what to scrape"
echo ""
pause

# ── Step 3: Point at where to watch the data (Grafana + Console Observe) ─────
step "Where to watch the metrics..."
CONSOLE_URL="$(get_console_url)"
GRAFANA_HOST="$(oc get route -n "${OBS_GRAFANA_NS}" \
  -o jsonpath='{range .items[*]}{.spec.host}{"\n"}{end}' 2>/dev/null | grep -i grafana | head -n1 || true)"
echo -e "  ${BOLD}OpenShift Console → Observe → Metrics / Targets / Dashboards:${RESET}"
echo -e "    ${CYAN}${CONSOLE_URL}/monitoring${RESET}"
if [[ -n "${GRAFANA_HOST}" ]]; then
  echo -e "  ${BOLD}Grafana (CL dashboards):${RESET} ${CYAN}https://${GRAFANA_HOST}${RESET}"
else
  echo -e "  ${YELLOW}Grafana route not found in '${OBS_GRAFANA_NS}' — see observability/how-to-setup-monitor.md.${RESET}"
fi
echo ""
echo -e "  ${BOLD}CL Grafana dashboards (import by ID):${RESET}"
echo -e "    App Developer ${CYAN}21538${RESET}   Platform Engineer ${CYAN}20982${RESET}   Business User ${CYAN}20981${RESET}   DNS Operator ${CYAN}22695${RESET}"
echo ""
pause

# ── Step 4: Resolve how to reach the routes (scheme/port from the Gateway) ───
GW_ADDR="$(oc get gateway "${GATEWAY_NAME}" -n "${GATEWAY_NAMESPACE}" \
  -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)"
GATEWAY_DOMAIN_RESOLVED="$(get_gateway_domain)"
if oc get gateway "${GATEWAY_NAME}" -n "${GATEWAY_NAMESPACE}" \
     -o jsonpath='{.spec.listeners[*].name}' 2>/dev/null | grep -qw https; then
  SCHEME="https"; PORT=443; CURL_TLS="-k"
else
  SCHEME="http"; PORT=80; CURL_TLS=""
fi

# Primary route (steps 13/16). Add the API key if an AuthPolicy guards it.
APP_HOST="${APP_NAME}.${GATEWAY_DOMAIN_RESOLVED}"
APP_URL="${SCHEME}://${APP_HOST}/api/info"
APP_AUTH_ARGS=()
if oc get authpolicy "${AUTH_POLICY_NAME}" -n "${DEMO_PROJECT}" &>/dev/null; then
  APP_AUTH_ARGS=(-H "Authorization: ${AUTH_HEADER_PREFIX} ${AUTH_API_KEY_VALUE}")
fi

# Per-tier route (step 17), if it exists — drives gold/silver/deny traffic.
MTLS_HOST="${MTLS_ROUTE_NAME}.${GATEWAY_DOMAIN_RESOLVED}"
MTLS_URL="${SCHEME}://${MTLS_HOST}/api/info"
HAVE_MTLS_ROUTE=false
if oc get httproute "${MTLS_ROUTE_NAME}" -n "${DEMO_PROJECT}" &>/dev/null; then
  HAVE_MTLS_ROUTE=true
fi

# Send one request to the primary route; echo the status code.
hit_app() {
  curl -s ${CURL_TLS} -o /dev/null -w '%{http_code}' \
    --resolve "${APP_HOST}:${PORT}:${GW_ADDR}" \
    "${APP_AUTH_ARGS[@]}" "${APP_URL}" 2>/dev/null || echo "000"
}

# Send one request to the per-tier route as a given client; echo the status code.
hit_mtls() { # $1 = X-Client-Id value
  curl -s ${CURL_TLS} -o /dev/null -w '%{http_code}' \
    --resolve "${MTLS_HOST}:${PORT}:${GW_ADDR}" \
    -H "${MTLS_CLIENT_HEADER}: $1" "${MTLS_URL}" 2>/dev/null || echo "000"
}

# ── Step 5: Label the HTTPRoutes so the per-app dashboard panels join ────────
# The CL example dashboards join low-level Istio/Envoy metrics with Gateway API
# state metrics ONLY when each HTTPRoute carries `service` and `deployment`
# labels whose values match the backend Service/Deployment. Without these the
# App Developer / Business User per-API panels stay empty even with traffic.
step "Labelling HTTPRoutes with service/deployment so the per-app panels populate..."
show_cmd "oc label httproute ${APP_NAME} -n ${DEMO_PROJECT} \\
  service=${APP_NAME} deployment=${APP_NAME} --overwrite"
oc label httproute "${APP_NAME}" -n "${DEMO_PROJECT}" \
  service="${APP_NAME}" deployment="${APP_NAME}" --overwrite >/dev/null \
  && ok "HTTPRoute '${APP_NAME}' labelled (service=${APP_NAME}, deployment=${APP_NAME})" \
  || warn "Could not label HTTPRoute '${APP_NAME}' — does it exist? (run scripts/13-http-route.sh)"
if ${HAVE_MTLS_ROUTE}; then
  # The step-17 route shares the SAME backend Service/Deployment as the primary route.
  oc label httproute "${MTLS_ROUTE_NAME}" -n "${DEMO_PROJECT}" \
    service="${APP_NAME}" deployment="${APP_NAME}" --overwrite >/dev/null \
    && ok "HTTPRoute '${MTLS_ROUTE_NAME}' labelled (service=${APP_NAME}, deployment=${APP_NAME})" \
    || warn "Could not label HTTPRoute '${MTLS_ROUTE_NAME}'"
fi
echo ""
pause

# ── Step 6: Generate sustained traffic so the dashboards light up ────────────
step "Generating traffic so the dashboards populate (istio_requests_total needs flow)..."
if [[ -z "${GW_ADDR}" || -z "${GATEWAY_DOMAIN_RESOLVED}" ]]; then
  warn "Gateway address/domain unavailable — cannot send traffic. Run scripts/13-http-route.sh first."
  exit 1
fi

echo -e "  ${BOLD}Primary route :${RESET} ${CYAN}${APP_URL}${RESET}"
if ${HAVE_MTLS_ROUTE}; then
  echo -e "  ${BOLD}Per-tier route:${RESET} ${CYAN}${MTLS_URL}${RESET}  (clients: ${MTLS_GOLD_CLIENT}/${MTLS_SILVER_CLIENT}/${MTLS_UNKNOWN_CLIENT})"
fi
echo -e "  ${YELLOW}${OBS_TRAFFIC_ROUNDS} batches, ${OBS_TRAFFIC_DELAY}s apart — mixing 200s, 429s and 403s for varied panels.${RESET}"
echo ""

show_cmd "# Drive mixed traffic through the Gateway (re-run to keep dashboards busy)
for r in \$(seq 1 ${OBS_TRAFFIC_ROUNDS}); do
  curl -s ${CURL_TLS} --resolve ${APP_HOST}:${PORT}:${GW_ADDR} \\
    -H 'Authorization: ${AUTH_HEADER_PREFIX} <api-key>' ${APP_URL}        # 200 / 429
  curl -s ${CURL_TLS} --resolve ${MTLS_HOST}:${PORT}:${GW_ADDR} \\
    -H '${MTLS_CLIENT_HEADER}: ${MTLS_GOLD_CLIENT}'   ${MTLS_URL}         # gold
  curl -s ${CURL_TLS} --resolve ${MTLS_HOST}:${PORT}:${GW_ADDR} \\
    -H '${MTLS_CLIENT_HEADER}: ${MTLS_UNKNOWN_CLIENT}' ${MTLS_URL}        # 403
  sleep ${OBS_TRAFFIC_DELAY}
done"

declare -A tally=()
total=0
for r in $(seq 1 "${OBS_TRAFFIC_ROUNDS}"); do
  codes=()
  codes+=("$(hit_app)")
  if ${HAVE_MTLS_ROUTE}; then
    codes+=("$(hit_mtls "${MTLS_GOLD_CLIENT}")")
    codes+=("$(hit_mtls "${MTLS_SILVER_CLIENT}")")
    codes+=("$(hit_mtls "${MTLS_UNKNOWN_CLIENT}")")
  fi
  line=""
  for c in "${codes[@]}"; do
    tally[$c]=$(( ${tally[$c]:-0} + 1 ))
    total=$((total + 1))
    case "$c" in
      2*) line+=" ${GREEN}${c}${RESET}" ;;
      4*) line+=" ${YELLOW}${c}${RESET}" ;;
      *)  line+=" ${RED}${c}${RESET}" ;;
    esac
  done
  printf "  Batch %2d/%d:%b\n" "${r}" "${OBS_TRAFFIC_ROUNDS}" "${line}"
  sleep "${OBS_TRAFFIC_DELAY}"
done
echo ""

step "Traffic summary (${total} requests sent):"
for code in $(printf '%s\n' "${!tally[@]:-}" | sort); do
  [[ -n "${code}" ]] || continue
  echo -e "  HTTP ${code}: ${BOLD}${tally[$code]}${RESET}"
done
echo ""

echo -e "${YELLOW}  Open Grafana now — request rate, error rate and 429s should be visible.${RESET}"
echo -e "${YELLOW}  Re-run this script to keep traffic flowing while you tour the dashboards.${RESET}"
echo ""
ok "ACT 4 — Observe API Connectivity complete"

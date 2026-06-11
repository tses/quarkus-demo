#!/usr/bin/env bash
# =============================================================================
# demo-config.sh — Central configuration for all demo scripts
# Source this file at the top of every script: source "$(dirname "$0")/demo-config.sh"
# =============================================================================

# -----------------------------------------------------------------------------
# CLUSTER SETTINGS — auto-detected from active oc login session
# Run: oc login <cluster-url> before starting the demo. No need to edit these.
# -----------------------------------------------------------------------------
# OCP_CONSOLE_URL is derived lazily at runtime — do NOT evaluate at source time
# to avoid DNS issues. Use: oc whoami --show-console  (OCP 4.x)
get_console_url() {
  oc whoami --show-console 2>/dev/null || \
    echo "https://console-openshift-console.apps.$(oc whoami --show-server 2>/dev/null | sed 's|https://api\.||;s|:6443||')"
}

# -----------------------------------------------------------------------------
# PROJECT / NAMESPACE — change this if you want a different namespace name
# -----------------------------------------------------------------------------
export DEMO_PROJECT_CONSOLE="ocp-demo-app-console"
export DEMO_PROJECT_CONSOLE_DISPLAY="OCP Demo App Console"
export DEMO_PROJECT="ocp-demo"
export DEMO_PROJECT_DISPLAY="OCP Introduction Demo"

# -----------------------------------------------------------------------------
# APPLICATION — quarkus-quickstarts/getting-started
# -----------------------------------------------------------------------------
export APP_NAME="ocp-demo-app"
export APP_NAME_V2="ocp-demo-app-v2"
export GIT_REPO="https://github.com/tses/quarkus-demo"   # ← update to your fork
export GIT_CONTEXT_DIR="app/ocp-demo-app"
export GIT_REF_V1="main"
export GIT_REF_V2="main"                      # same repo, patch APP_COLOUR=green for v2
export BUILDER_IMAGE="java:openjdk-17-ubi8"   # java imagestream in openshift namespace

# -----------------------------------------------------------------------------
# DATABASE (Postgres Operator) — lives in its OWN namespace (separate from app)
# -----------------------------------------------------------------------------
export DB_CLUSTER_NAME="demo-db"
export DB_NAMESPACE="ocp-demo-db"
export DB_NAMESPACE_DISPLAY="OCP Demo Database"

# -----------------------------------------------------------------------------
# ACT 4 — CONNECTIVITY LINK / GATEWAY API (Kuadrant)
# The Gateway is reconciled by the gateway controller available on the cluster.
# On OpenShift the built-in GatewayClass is "openshift-default". With OpenShift
# Connectivity Link (Kuadrant) the Istio controller exposes the "istio" class.
# Adjust GATEWAY_CLASS to match `oc get gatewayclass` on your cluster.
# -----------------------------------------------------------------------------
export GATEWAY_NAME="demo-gateway"
export GATEWAY_CLASS="openshift-default"
export GATEWAY_NAMESPACE="${DEMO_PROJECT}"
# Gateway API listeners use a DEDICATED subdomain, separate from the default
# Router/Route wildcard (*.apps.<cluster>). Leave empty to auto-derive it from
# the apps domain by swapping the leading "apps." prefix for "api.".
export GATEWAY_DOMAIN=""

# ── TLSPolicy (step 14) — cert-manager issuer used to secure the Gateway ─────
# The Gateway gains an HTTPS listener whose certificate is provisioned by
# cert-manager via the issuer referenced below. The demo cluster ships a
# Ready "self-signed" ClusterIssuer; swap to a real (e.g. ACME/Let's Encrypt)
# issuer for production-like certs.
export GATEWAY_TLS_POLICY_NAME="demo-gateway-tls"
export GATEWAY_TLS_SECRET="demo-gateway-tls"
export GATEWAY_TLS_ISSUER="self-signed"
export GATEWAY_TLS_ISSUER_KIND="ClusterIssuer"

# ── AuthPolicy (step 15) — protect the exposed API with API key auth ─────────
# Kuadrant's Authorino enforces authentication at the Gateway. The demo uses
# API key authentication: callers must send `Authorization: APIKEY <key>`.
# API keys are stored as labelled Secrets that Authorino reconciles.
export AUTH_POLICY_NAME="demo-app-auth"
export AUTH_API_KEY_SECRET="demo-app-apikey"
export AUTH_API_KEY_LABEL="${APP_NAME}"          # value of the app label selector
export AUTH_API_KEY_VALUE="demo-secret-key-123"  # the demo API key (not for prod!)
export AUTH_HEADER_PREFIX="APIKEY"

# ── RateLimitPolicy (step 16) — throttle request volume on the API ───────────
# Kuadrant's Limitador enforces request quotas at the Gateway. The demo uses a
# deliberately low limit so the throttle is easy to trigger live: after
# RATE_LIMIT requests within RATE_WINDOW, further calls get HTTP 429.
export RATE_LIMIT_POLICY_NAME="demo-app-ratelimit"
export RATE_LIMIT="5"          # max requests allowed per window
export RATE_WINDOW="10s"       # rolling window (Limitador duration syntax)
export RATE_LIMIT_BURST="8"    # how many calls the demo fires to cross the limit

# ── External metadata authorization (step 17) — separate route + FQDN ────────
# A SECOND HTTPRoute on its own hostname (same Gateway, same backend Service)
# demonstrates dynamic, runtime authorization. This route does NOT authenticate
# (anonymous) — it trusts a client identity header forwarded by an upstream WAF
# (mTLS at the edge). Authorino fetches the caller's tier LIVE from an external
# metadata service and a RateLimitPolicy applies a per-tier, per-client quota.
export MTLS_ROUTE_NAME="${APP_NAME}-mtls"          # new HTTPRoute (FQDN: <name>.api.<domain>)
export MTLS_AUTH_POLICY_NAME="demo-app-mtls-auth"  # anonymous + external metadata
export MTLS_RL_POLICY_NAME="demo-app-mtls-rl"      # per-tier rate limit
export META_SVC_NAME="metadata-svc"                # external metadata service
export META_SVC_PORT="8080"
export MTLS_CLIENT_HEADER="X-Client-Id"            # identity header set by the WAF
# Demo clients → tier mapping (kept in sync with the metadata-svc tier map).
export MTLS_GOLD_CLIENT="user1"
export MTLS_GOLD_LIMIT="5"
export MTLS_SILVER_CLIENT="user2"
export MTLS_SILVER_LIMIT="2"
export MTLS_TIER_WINDOW="10s"
export MTLS_UNKNOWN_CLIENT="ghost"   # not in the tier map → rejected (403)
export MTLS_BURST="7"                # calls fired per client to cross the limit

# ── Observability (step 18) — generate traffic so Grafana dashboards light up ─
# CL plugs into the cluster's user-workload monitoring. Dashboards (and
# istio_requests_total) only populate once requests flow through the Gateway.
# This step fires a steady stream of requests across the step-13/16 route and
# the step-17 per-tier route so request-rate / error-rate / 429 panels fill in.
export OBS_KUADRANT_NAME="kuadrant"        # Kuadrant CR carrying spec.observability
export OBS_KUADRANT_NS="kuadrant-system"   # namespace of the Kuadrant CR
export OBS_GRAFANA_NS="monitoring"         # namespace hosting Grafana
export OBS_TRAFFIC_ROUNDS="30"             # number of request batches to send
export OBS_TRAFFIC_DELAY="2"               # seconds between batches

# -----------------------------------------------------------------------------
# COLORS — for pretty terminal output during demo
# -----------------------------------------------------------------------------
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export CYAN='\033[0;36m'
export BOLD='\033[1m'
export RESET='\033[0m'

# -----------------------------------------------------------------------------
# HELPER FUNCTIONS
# -----------------------------------------------------------------------------

# Print a section header
header() {
  echo ""
  echo -e "${CYAN}${BOLD}══════════════════════════════════════════════${RESET}"
  echo -e "${CYAN}${BOLD}  $1${RESET}"
  echo -e "${CYAN}${BOLD}══════════════════════════════════════════════${RESET}"
  echo ""
}

# Print a step
step() {
  echo -e "${YELLOW}▶ $1${RESET}"
}

# Print success
ok() {
  echo -e "${GREEN}✔ $1${RESET}"
}

# Print warning
warn() {
  echo -e "${RED}⚠ $1${RESET}"
}

# Wait for user to press Enter (pacing during live demo)
pause() {
  echo ""
  echo -e "${BOLD}[Press ENTER to continue...]${RESET}"
  read -r
}

# Wait for a deployment to be ready
wait_for_deployment() {
  local name=$1
  local ns=${2:-$DEMO_PROJECT}
  step "Waiting for deployment/${name} to be ready..."
  oc rollout status deployment/"${name}" -n "${ns}" --timeout=300s
  ok "deployment/${name} is ready"
}

# Wait for a pod label to be running
wait_for_pods() {
  local selector=$1
  local ns=${2:-$DEMO_PROJECT}
  step "Waiting for pods (${selector}) to be Running..."
  oc wait pod -l "${selector}" -n "${ns}" \
    --for=condition=Ready \
    --timeout=300s
  ok "Pods are ready"
}

# Show a command (or YAML block) before executing — gives presenter time to explain
# Usage:  show_cmd "oc new-app ..."
show_cmd() {
  local _B=$'\033[1m' _Y=$'\033[1;33m' _C=$'\033[0;36m' _R=$'\033[0m'
  printf "\n"
  printf "%s┌─ Command ────────────────────────────────────────────────────┐%s\n" "${_B}${_Y}" "${_R}"
  while IFS= read -r line; do
    printf "%s│%s  %s%s%s\n" "${_B}${_Y}" "${_R}" "${_C}" "${line}" "${_R}"
  done <<< "$1"
  printf "%s└──────────────────────────────────────────────────────────────┘%s\n" "${_B}${_Y}" "${_R}"
  printf "\n"
  printf "%s[Press ENTER to run ↑]%s " "${_B}" "${_R}"
  read -r < /dev/tty
}

# Check oc is logged in
check_login() {
  if ! oc whoami &>/dev/null; then
    warn "Not logged in to OpenShift. Run: oc login ${OCP_API_URL}"
    exit 1
  fi
  ok "Logged in as: $(oc whoami)"
}

# Ensure we're in the right project
use_project() {
  oc project "${DEMO_PROJECT}" &>/dev/null || \
    oc new-project "${DEMO_PROJECT}" --display-name="${DEMO_PROJECT_DISPLAY}"
  ok "Using project: ${DEMO_PROJECT}"
}

# Return the cluster's wildcard apps domain (e.g. apps.cluster.example.com)
# Used to build Route hostnames.
get_apps_domain() {
  oc get ingresses.config.openshift.io cluster \
    -o jsonpath='{.spec.domain}' 2>/dev/null
}

# Return the domain used for Gateway API listener/route hostnames in ACT 4.
# Precedence:
#   1. GATEWAY_DOMAIN if explicitly set in this config
#   2. The apps domain with its leading "apps." replaced by "api."
#      (e.g. apps.mini.example.com -> api.mini.example.com)
get_gateway_domain() {
  if [[ -n "${GATEWAY_DOMAIN:-}" ]]; then
    echo "${GATEWAY_DOMAIN}"
    return
  fi
  local apps_domain
  apps_domain="$(get_apps_domain)"
  if [[ -n "${apps_domain}" ]]; then
    echo "${apps_domain/#apps./api.}"
  fi
}

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
# DATABASE (Postgres Operator)
# -----------------------------------------------------------------------------
export DB_CLUSTER_NAME="demo-db"
export DB_NAMESPACE="${DEMO_PROJECT}"

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

#!/usr/bin/env bash
# =============================================================================
# 00-setup.sh — Pre-demo setup: login, create project, verify cluster
# Run this BEFORE entering the room.
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/demo-config.sh"

# Derive API URL from active oc session
OCP_API_URL=$(oc whoami --show-server 2>/dev/null || echo "unknown")

header "OCP Demo — Pre-flight Setup"

# 1. Check login
step "Checking OpenShift login..."
check_login

# 2. Create / switch to console demo project (for UI-based demo 02-deploy-s2i)
step "Setting up project '${DEMO_PROJECT_CONSOLE}'..."
if oc get project "${DEMO_PROJECT_CONSOLE}" &>/dev/null; then
  warn "Project '${DEMO_PROJECT_CONSOLE}' already exists. Cleaning up..."
  oc delete project "${DEMO_PROJECT_CONSOLE}" --wait=true || true
  sleep 5
fi
oc new-project "${DEMO_PROJECT_CONSOLE}" --display-name="${DEMO_PROJECT_CONSOLE_DISPLAY}"
ok "Project '${DEMO_PROJECT_CONSOLE}' created (use this in the UI for demo 02)"

# 3. Create / switch to main demo project
step "Setting up project '${DEMO_PROJECT}'..."
if oc get project "${DEMO_PROJECT}" &>/dev/null; then
  warn "Project '${DEMO_PROJECT}' already exists. Cleaning up..."
  oc delete project "${DEMO_PROJECT}" --wait=true || true
  sleep 5
fi
oc new-project "${DEMO_PROJECT}" --display-name="${DEMO_PROJECT_DISPLAY}"
ok "Project '${DEMO_PROJECT}' created"

# 4. Verify nodes are ready
step "Checking cluster nodes..."
oc get nodes
NODE_COUNT=$(oc get nodes --no-headers | grep -c " Ready")
ok "${NODE_COUNT} node(s) Ready"

# 5. Verify OperatorHub is accessible
step "Checking OperatorHub..."
if oc get operatorhub cluster &>/dev/null; then
  ok "OperatorHub is available"
else
  warn "OperatorHub not found — Postgres operator demo may not work"
fi

# 6. Pre-pull builder image (speeds up S2I during demo)
step "Warming up Java S2I builder image (optional)..."
oc import-image java:latest \
  --from=registry.access.redhat.com/ubi9/openjdk-21:latest \
  --confirm \
  --scheduled=false \
  -n "${DEMO_PROJECT}" 2>/dev/null || true
ok "Builder image ready"

# 7. Print console URL
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${GREEN}${BOLD}  SETUP COMPLETE — Ready to demo!${RESET}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "  API     : ${CYAN}${OCP_API_URL}${RESET}"
echo -e "  Project : ${CYAN}${DEMO_PROJECT}${RESET}"
echo -e "  User    : ${CYAN}$(oc whoami)${RESET}"
echo ""
echo -e "${YELLOW}  Open browser tabs NOW:${RESET}"
echo -e "  1. $(oc whoami --show-console 2>/dev/null || echo 'OCP Console')"
echo -e "  2. ${GIT_REPO}/tree/main/${GIT_CONTEXT_DIR}"
echo ""

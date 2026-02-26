#!/usr/bin/env bash
# =============================================================================
# 99-teardown.sh — Clean up everything after the demo
# Safe to run multiple times (idempotent)
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/demo-config.sh"

header "Demo Teardown — Cleaning up"

check_login

warn "This will DELETE the project '${DEMO_PROJECT}' and ALL resources in it."
echo ""
echo -n "  Are you sure? (yes/no): "
read -r CONFIRM
if [[ "${CONFIRM}" != "yes" ]]; then
  echo "Aborted."
  exit 0
fi

# ── Delete the console demo project ──────────────────────────────────────────
step "Deleting project '${DEMO_PROJECT_CONSOLE}'..."
oc delete project "${DEMO_PROJECT_CONSOLE}" --wait=false 2>/dev/null || true
ok "Project '${DEMO_PROJECT_CONSOLE}' deletion initiated (runs in background)"
echo ""

# ── Delete the main demo project (removes everything inside) ─────────────────
step "Deleting project '${DEMO_PROJECT}'..."
oc delete project "${DEMO_PROJECT}" --wait=false 2>/dev/null || true
ok "Project '${DEMO_PROJECT}' deletion initiated (runs in background)"
echo ""

# ── Uninstall Postgres Operator (cluster-scoped — optional) ──────────────────
step "Checking for Postgres Operator subscription..."
SUB=$(oc get subscription -n "${DEMO_PROJECT}" \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [[ -n "${SUB}" ]]; then
  oc delete subscription "${SUB}" -n "${DEMO_PROJECT}" 2>/dev/null || true
  ok "Subscription removed"
else
  ok "No subscription found (already cleaned up or never installed)"
fi

echo ""
echo -e "${GREEN}${BOLD}Teardown complete.${RESET}"
echo -e "  Project '${DEMO_PROJECT_CONSOLE}' is being deleted."
echo -e "  Project '${DEMO_PROJECT}' is being deleted."
echo -e "  Run ${CYAN}oc get project ${DEMO_PROJECT_CONSOLE} ${DEMO_PROJECT}${RESET} to confirm deletion."
echo ""

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

# ── Delete the database namespace ────────────────────────────────────────────
step "Deleting database project '${DB_NAMESPACE}'..."
oc delete project "${DB_NAMESPACE}" --wait=false 2>/dev/null || true
ok "Project '${DB_NAMESPACE}' deletion initiated (runs in background)"
echo ""

# ── ACT 5 GitOps: Argo CD objects first (otherwise Argo CD keeps syncing) ────
oc delete applications.argoproj.io "${ARGO_APP}" -n "${ARGO_NAMESPACE}" --ignore-not-found >/dev/null 2>&1 || true
oc delete appprojects.argoproj.io "${ARGO_PROJECT}" -n "${ARGO_NAMESPACE}" --ignore-not-found >/dev/null 2>&1 || true
oc delete secret "${GITOPS_PROJECT}-repo" -n "${ARGO_NAMESPACE}" --ignore-not-found >/dev/null 2>&1 || true
oc delete role,rolebinding ked-demo-pipeline-app-reader -n "${ARGO_NAMESPACE}" --ignore-not-found >/dev/null 2>&1 || true

# ── Delete the ACT 5 CI/CD namespaces ────────────────────────────────────────
for ns in "${CICD_PROJECT}" "${DEV_PROJECT}"; do
  step "Deleting project '${ns}'..."
  oc delete project "${ns}" --wait=false 2>/dev/null || true
  ok "Project '${ns}' deletion initiated (runs in background)"
done
echo ""

# ── GitLab (ACT 5 pre-demo infrastructure) — kept unless explicitly confirmed ─
if oc get project "${GITLAB_NAMESPACE}" &>/dev/null; then
  echo -n "  Also delete GitLab namespace '${GITLAB_NAMESPACE}' (repos, registry images, credentials)? (yes/no): "
  read -r CONFIRM_GITLAB
  if [[ "${CONFIRM_GITLAB}" == "yes" ]]; then
    oc delete project "${GITLAB_NAMESPACE}" --wait=false 2>/dev/null || true
    ok "Project '${GITLAB_NAMESPACE}' deletion initiated (runs in background)"
  else
    ok "GitLab kept for the next session"
  fi
  echo ""
fi

# ── Uninstall Postgres Operator subscription (lives in DB namespace) ──────────
step "Checking for Postgres Operator subscription in '${DB_NAMESPACE}'..."
SUB=$(oc get subscription -n "${DB_NAMESPACE}" \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [[ -n "${SUB}" ]]; then
  oc delete subscription "${SUB}" -n "${DB_NAMESPACE}" 2>/dev/null || true
  ok "Subscription removed"
else
  ok "No subscription found (already cleaned up or never installed)"
fi

echo ""
echo -e "${GREEN}${BOLD}Teardown complete.${RESET}"
echo -e "  Project '${DEMO_PROJECT_CONSOLE}' is being deleted."
echo -e "  Project '${DEMO_PROJECT}' is being deleted."
echo -e "  Project '${DB_NAMESPACE}' is being deleted."
echo -e "  Projects '${CICD_PROJECT}' and '${DEV_PROJECT}' are being deleted."
echo -e "  Run ${CYAN}oc get project ${DEMO_PROJECT_CONSOLE} ${DEMO_PROJECT} ${DB_NAMESPACE} ${CICD_PROJECT} ${DEV_PROJECT}${RESET} to confirm deletion."
echo ""

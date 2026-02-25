#!/usr/bin/env bash
# =============================================================================
# 04-deployment-strategies.sh — Rolling update, rollback demo
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/demo-config.sh"

header "ACT 3 — Deployment Strategies"

check_login
use_project

# ── Step 1: Show current strategy ─────────────────────────────────────────────
step "Current deployment strategy:"
echo ""
echo -e "${CYAN}  RollingUpdate parameters:${RESET}"
echo -e "${CYAN}    maxSurge: 25%${RESET}        — how many EXTRA pods OpenShift can create above the"
echo -e "${CYAN}                    ${RESET}        desired count during the update."
echo -e "${CYAN}                    ${RESET}        (e.g. 4 replicas → up to 5 pods running at once)"
echo -e "${CYAN}    maxUnavailable: 25%${RESET}  — how many pods can be unavailable at the same time."
echo -e "${CYAN}                    ${RESET}        (e.g. 4 replicas → at least 3 always serving traffic)"
echo ""
echo -e "${CYAN}  Together they guarantee zero-downtime: new pods come up BEFORE old ones go down.${RESET}"
echo ""
pause
oc get deployment "${APP_NAME}" -n "${DEMO_PROJECT}" \
  -o jsonpath='Strategy: {.spec.strategy.type}{"\n"}MaxSurge: {.spec.strategy.rollingUpdate.maxSurge}{"\n"}MaxUnavailable: {.spec.strategy.rollingUpdate.maxUnavailable}{"\n"}'
echo ""
pause

# ── Step 2: Show rollout history ──────────────────────────────────────────────
step "Rollout history:"
oc rollout history deployment/"${APP_NAME}" -n "${DEMO_PROJECT}"
echo ""
pause

# ── Step 3: Trigger a new rollout (simulate new image) ────────────────────────
step "Triggering a new rollout (simulating a new image deploy)..."
echo -e "${YELLOW}  Watch the Topology view in the Console — pods will cycle${RESET}"
echo ""

# Inject APP_VERSION env var — MicroProfile maps app.version → APP_VERSION
# so /api/info will show the updated version value live
DEMO_VER="v$(date +%s)"
show_cmd "oc set env deployment/${APP_NAME}
  APP_VERSION=${DEMO_VER}
  -n ${DEMO_PROJECT}"
oc set env deployment/"${APP_NAME}" \
  APP_VERSION="${DEMO_VER}" \
  -n "${DEMO_PROJECT}"

# Annotate so rollout history shows a meaningful CHANGE-CAUSE
oc annotate deployment/"${APP_NAME}" \
  kubernetes.io/change-cause="demo rollout ${DEMO_VER}" \
  --overwrite \
  -n "${DEMO_PROJECT}"

echo ""
step "Watching rollout (switch to Console Topology view now!):"
oc rollout status deployment/"${APP_NAME}" -n "${DEMO_PROJECT}" --timeout=120s
echo ""
ok "Rolling update complete — zero downtime!"
pause

# ── Step 4: Show updated history ──────────────────────────────────────────────
step "Updated rollout history:"
oc rollout history deployment/"${APP_NAME}" -n "${DEMO_PROJECT}"
echo ""
pause

# ── Step 5: Rollback ──────────────────────────────────────────────────────────
step "Rolling BACK to previous version (one command)..."
show_cmd "oc rollout undo deployment/${APP_NAME}
  -n ${DEMO_PROJECT}"
oc rollout undo deployment/"${APP_NAME}" -n "${DEMO_PROJECT}"
oc rollout status deployment/"${APP_NAME}" -n "${DEMO_PROJECT}" --timeout=120s
echo ""
ok "Rollback complete. Previous version is live again."
echo ""

# ── Step 6: Explain Recreate (without doing it — avoids downtime during demo) ──
step "Recreate strategy (explanation only):"
cat << 'EOF'

  spec:
    strategy:
      type: Recreate          # ALL old pods stop first → THEN new pods start
                              # Use when 2 versions CANNOT run simultaneously
                              # (e.g. DB schema migration)

  vs.

  spec:
    strategy:
      type: RollingUpdate     # New pods UP before old pods DOWN → Zero downtime
      rollingUpdate:
        maxSurge: 25%
        maxUnavailable: 25%

EOF
echo ""
ok "Deployment strategies demo complete."

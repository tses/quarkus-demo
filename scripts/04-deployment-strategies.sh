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

# Inject a new env var to force a new rollout revision
oc set env deployment/"${APP_NAME}" \
  DEMO_VERSION="v$(date +%s)" \
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

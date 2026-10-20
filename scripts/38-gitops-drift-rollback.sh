#!/usr/bin/env bash
# =============================================================================
# 38-gitops-drift-rollback.sh — ACT 5: self-heal and rollback with Git
#
#   1. Drift: change the cluster by hand (`oc scale`, `oc delete service`) →
#      Argo CD (selfHeal) puts it back to what Git says, within seconds.
#   2. Rollback: `git revert` of the last image commit in the gitops repo →
#      Argo CD syncs the previous image. No pipeline, no oc — just Git.
#
# Prerequisites: step 36 (Application) and ideally 37 (pipeline image commits).
# Idempotent: drift is reverted by Argo CD; each run reverts the latest commit
# that changed the overlay (running it twice = rollback, then roll forward).
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/demo-config.sh"

header "ACT 5 — GitOps: drift and rollback"

check_login
command -v jq &>/dev/null || { warn "'jq' not found in PATH"; exit 1; }
argo_enabled || { warn "Argo CD Application '${ARGO_APP}' not found — run scripts/36-gitops-setup.sh first"; exit 1; }

GITLAB_URL="https://$(get_gitlab_host)"
GL_API="${GITLAB_URL}/api/v4"
ROOT_TOKEN="$(get_gitlab_cred root-token)"
GITOPS_PATH="${GITLAB_GROUP}/${GITOPS_PROJECT}"
GITOPS_ENC="${GITOPS_PATH//\//%2F}"
OVERLAY_FILE="${GITOPS_OVERLAY}/kustomization.yaml"
ARGO_URL="https://$(oc get route openshift-gitops-server -n "${ARGO_NAMESPACE}" -o jsonpath='{.spec.host}')"

gl_api() {
  local method="$1" path="$2"; shift 2
  curl -sk -X "${method}" -H "PRIVATE-TOKEN: ${ROOT_TOKEN}" -H 'Content-Type: application/json' "${GL_API}${path}" "$@"
}
app_field() { oc get application "${ARGO_APP}" -n "${ARGO_NAMESPACE}" -o jsonpath="$1" 2>/dev/null; }
dev_image() { oc get deployment "${APP_NAME}" -n "${DEV_PROJECT}" -o jsonpath='{.spec.template.spec.containers[0].image}'; }
replicas() { oc get deployment "${APP_NAME}" -n "${DEV_PROJECT}" -o jsonpath='{.spec.replicas}'; }

echo -e "  ${BOLD}Argo CD UI:${RESET} ${CYAN}${ARGO_URL}/applications/${ARGO_NAMESPACE}/${ARGO_APP}${RESET}  (keep it open)"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# PART 1 — Drift
# ─────────────────────────────────────────────────────────────────────────────
header "PART 1 — Someone changes the cluster by hand"

cat <<'MSG'
  Git says: 1 replica, a Service, a Route. selfHeal=true means Argo CD
  continuously compares and puts the live state back — the cluster cannot
  silently diverge from Git.
MSG
echo ""

step "Scale the deployment to 3 replicas with oc"
show_cmd "oc scale deployment ${APP_NAME} --replicas=3 -n ${DEV_PROJECT}" \
  "Scale the deployment (manual drift)" \
  "Console → Workloads → Deployments → ${APP_NAME} → Details → ▲ pod count arrow"
oc scale deployment "${APP_NAME}" --replicas=3 -n "${DEV_PROJECT}"
for i in $(seq 1 30); do
  R="$(replicas)"
  echo "  [${i}s] spec.replicas=${R}  sync=$(app_field '{.status.sync.status}')"
  [[ "${R}" == "1" && "${i}" -gt 1 ]] && break
  sleep 1
done
[[ "$(replicas)" == "1" ]] && ok "Argo CD reverted the drift: back to 1 replica (as in Git)" \
  || warn "Still $(replicas) replicas — is selfHeal enabled on the Application?"
echo ""
pause

step "Delete the Service"
show_cmd "oc delete service ${APP_NAME} -n ${DEV_PROJECT}" \
  "Delete the Service" \
  "Console → Networking → Services → ${APP_NAME} → Actions → Delete Service"
oc delete service "${APP_NAME}" -n "${DEV_PROJECT}" --wait=true
for i in $(seq 1 30); do
  oc get service "${APP_NAME}" -n "${DEV_PROJECT}" &>/dev/null && break
  echo "  [${i}s] service missing — sync=$(app_field '{.status.sync.status}')"
  sleep 1
done
oc get service "${APP_NAME}" -n "${DEV_PROJECT}" &>/dev/null \
  && ok "Service re-created by Argo CD ($(oc get service "${APP_NAME}" -n "${DEV_PROJECT}" -o jsonpath='{.metadata.creationTimestamp}'))" \
  || warn "Service not re-created yet — check the Argo CD UI"
echo ""
cat <<'MSG'
  The right way to scale or change anything: a commit to the gitops repo
  (overlays/dev), reviewed like code. Argo CD applies it.
MSG
echo ""
pause

# ─────────────────────────────────────────────────────────────────────────────
# PART 2 — Rollback = git revert
# ─────────────────────────────────────────────────────────────────────────────
header "PART 2 — A bad release? Roll back with git revert"

step "Deployment history = history of the overlay in the gitops repo"
show_cmd "GET ${GL_API}/projects/${GITOPS_ENC}/repository/commits?path=${OVERLAY_FILE}" \
  "List the overlay's commit history" \
  "GitLab → ${GITOPS_PATH} → Code → Repository → ${OVERLAY_FILE} → History"
HISTORY="$(gl_api GET "/projects/${GITOPS_ENC}/repository/commits?ref_name=main&path=${OVERLAY_FILE//\//%2F}&per_page=5")"
jq -r '.[] | "  \(.short_id)  \(.created_at[0:19])  \(.author_name)  \(.title)"' <<< "${HISTORY}"
TARGET_SHA="$(jq -r '.[0].id // empty' <<< "${HISTORY}")"
TARGET_TITLE="$(jq -r '.[0].title // empty' <<< "${HISTORY}")"
if [[ -z "${TARGET_SHA}" || "${TARGET_TITLE}" == *"initial desired state"* ]]; then
  warn "Only the initial commit changed the overlay — run scripts/37-pipeline-gitops.sh first to have something to roll back"
  exit 0
fi
echo ""
IMAGE_BEFORE="$(dev_image)"
echo -e "  Running now: ${CYAN}${IMAGE_BEFORE}${RESET}"
echo ""
pause

step "Revert '${TARGET_TITLE}' (${TARGET_SHA:0:8})"
show_cmd "POST ${GL_API}/projects/${GITOPS_ENC}/repository/commits/${TARGET_SHA:0:8}/revert  { branch: main }" \
  "Revert the commit" \
  "GitLab → ${GITOPS_PATH} → Code → Commits → ${TARGET_SHA:0:8} → Options → Revert"
RESP="$(gl_api POST "/projects/${GITOPS_ENC}/repository/commits/${TARGET_SHA}/revert" --data '{"branch":"main"}')"
REVERT_SHA="$(jq -r '.id // empty' <<< "${RESP}")"
[[ -n "${REVERT_SHA}" ]] || { warn "Revert failed: ${RESP}"; exit 1; }
ok "Reverted: ${GITLAB_URL}/${GITOPS_PATH}/-/commit/${REVERT_SHA}"
echo ""

step "Argo CD picks up the commit (webhook) and syncs"
for i in $(seq 1 60); do
  read -r REV SYNC HEALTH <<< "$(app_field '{.status.sync.revision} {.status.sync.status} {.status.health.status}')"
  echo "  [$((i * 3))s] revision=${REV:0:8} sync=${SYNC} health=${HEALTH}"
  [[ "${REV}" == "${REVERT_SHA}" && "${SYNC}" == "Synced" && "${HEALTH}" == "Healthy" ]] && break
  sleep 3
done
echo ""
echo -e "  Before : ${CYAN}${IMAGE_BEFORE}${RESET}"
echo -e "  Now    : ${CYAN}$(dev_image)${RESET}"
[[ "$(dev_image)" != "${IMAGE_BEFORE}" ]] && ok "Rolled back by Argo CD — no pipeline, no oc, just Git" \
  || warn "Image unchanged — check the Argo CD UI"
echo ""
pause

step "Argo CD sync history"
show_cmd "oc get application ${ARGO_APP} -n ${ARGO_NAMESPACE} -o jsonpath='{.status.history}'" \
  "Show the Argo CD sync history" \
  "Argo CD → Applications → ${ARGO_APP} → History and rollback"
app_field '{.status.history}' | jq -r '.[-4:][] | "  #\(.id)  \(.deployedAt)  \(.revision[0:8])"'
echo ""
cat <<'MSG'
  • Rollback = revert a commit: reviewed, audited, repeatable
  • Argo CD's own "Rollback" button is disabled while auto-sync is on — Git stays
    the source of truth (a UI rollback would be undone by the next sync)
  • Roll forward: the next pipeline run (push to the app repo) commits a new
    image; running this script again reverts the revert
  • Config is Git too: edit overlays/dev/env-patch.yaml (APP_COLOUR blue → green)
    in GitLab → Argo CD rolls out new pods → /api/info shows the new colour
MSG
echo ""
ok "GitOps: drift self-healed, rollback done through Git."
echo ""

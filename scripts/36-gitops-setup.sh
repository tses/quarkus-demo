#!/usr/bin/env bash
# =============================================================================
# 36-gitops-setup.sh — ACT 5: OpenShift GitOps (Argo CD) takes over ocp-demo-dev
#
#   1. GitLab project GITLAB_GROUP/GITOPS_PROJECT = desired state of the dev
#      environment (Kustomize base + overlays/dev, seeded with the image that
#      runs today), project token for the pipeline, webhook → Argo CD.
#   2. Argo CD (default instance openshift-gitops): managed-by label on the
#      dev project, AppProject 'ked-demo' + repository, read-only RBAC for the
#      pipeline, Application '<app>-dev' (automated sync, prune, self-heal).
#   3. Argo CD ADOPTS the running app — Synced/Healthy, no restart.
#
# Prerequisites: steps 30, 32 (app running in DEV_PROJECT).
# Idempotent: the repo is seeded only while empty (GITOPS_RESEED=1 overwrites
# the manifests), token reused while valid, objects via `oc apply`.
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/demo-config.sh"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARGO_DIR="cicd/gitops/argocd"
cd "${REPO_ROOT}"

header "ACT 5 — GitOps: Argo CD takes over the dev environment"

check_login
for bin in jq curl envsubst; do
  command -v "${bin}" &>/dev/null || { warn "'${bin}' not found in PATH"; exit 1; }
done
oc get deployment "${APP_NAME}" -n "${DEV_PROJECT}" &>/dev/null || \
  { warn "deployment/${APP_NAME} not found in ${DEV_PROJECT} — run scripts/32-pipeline-build-deploy.sh first"; exit 1; }

GITLAB_URL="https://$(get_gitlab_host)"
GL_API="${GITLAB_URL}/api/v4"
ROOT_TOKEN="$(get_gitlab_cred root-token)"
[[ -n "${ROOT_TOKEN}" ]] || { warn "GitLab root token not found — run scripts/30-gitlab-setup.sh"; exit 1; }
GITOPS_PATH="${GITLAB_GROUP}/${GITOPS_PROJECT}"
GITOPS_ENC="${GITOPS_PATH//\//%2F}"
GITOPS_WEB="${GITLAB_URL}/${GITOPS_PATH}"
ARGO_URL="https://$(oc get route openshift-gitops-server -n "${ARGO_NAMESPACE}" -o jsonpath='{.spec.host}')"
CONSOLE_URL="$(get_console_url)"

gl_api() {
  local method="$1" path="$2"; shift 2
  curl -sk -X "${method}" -H "PRIVATE-TOKEN: ${ROOT_TOKEN}" -H 'Content-Type: application/json' "${GL_API}${path}" "$@"
}

# Seed values = what runs in the dev project right now → adoption without restart
CUR_IMAGE="$(oc get deployment "${APP_NAME}" -n "${DEV_PROJECT}" -o jsonpath='{.spec.template.spec.containers[0].image}')"
export IMAGE_REPO="${CUR_IMAGE%@*}" IMAGE_DIGEST="${CUR_IMAGE#*@}"
export GIT_COMMIT="$(oc get deployment "${APP_NAME}" -n "${DEV_PROJECT}" -o jsonpath='{.metadata.annotations.ked-demo/git-commit}')"
export PIPELINE_RUN="$(oc get deployment "${APP_NAME}" -n "${DEV_PROJECT}" -o jsonpath='{.metadata.annotations.ked-demo/pipeline-run}')"
export GITOPS_REPO_URL="$(get_gitops_repo_url)"
render() {
  envsubst '${ARGO_PROJECT} ${ARGO_NAMESPACE} ${ARGO_APP} ${GITOPS_REPO_URL} ${GITOPS_PROJECT} ${GITOPS_OVERLAY} ${DEV_PROJECT} ${CICD_PROJECT} ${IMAGE_REPO} ${IMAGE_DIGEST} ${GIT_COMMIT} ${PIPELINE_RUN}' < "$1"
}
app_state() {
  oc get application "${ARGO_APP}" -n "${ARGO_NAMESPACE}" \
    -o jsonpath='{.status.sync.status} {.status.health.status} {.status.sync.revision}' 2>/dev/null
}

# ─────────────────────────────────────────────────────────────────────────────
# PART 1 — Concept
# ─────────────────────────────────────────────────────────────────────────────
header "PART 1 — From push to pull"

cat <<'MSG'
  Until now the PIPELINE deployed (push model): it needed write access to the
  cluster, and nothing stopped manual changes from drifting away from Git.

  GitOps (pull model):
    • Git is the single source of truth for the desired state
    • Argo CD runs IN the cluster, compares Git with the live state, and syncs
    • Every change is a commit → review, audit trail, rollback = git revert

    app repo ──CI──► image ──commit──► gitops repo ◄──watch── Argo CD ──sync──► ocp-demo-dev
MSG
echo ""
pause

# ─────────────────────────────────────────────────────────────────────────────
# PART 2 — The gitops repo
# ─────────────────────────────────────────────────────────────────────────────
header "PART 2 — A separate repo for the desired state"

GROUP_ID="$(gl_api GET "/groups/${GITLAB_GROUP}" | jq -r '.id // empty')"
[[ -n "${GROUP_ID}" ]] || { warn "GitLab group '${GITLAB_GROUP}' not found"; exit 1; }
step "GitLab project '${GITOPS_PATH}' (public: Argo CD reads it anonymously)"
show_cmd "POST ${GL_API}/projects
  { name: ${GITOPS_PROJECT}, namespace_id: <${GITLAB_GROUP}>, visibility: public }"
GITOPS_ID="$(gl_api GET "/projects/${GITOPS_ENC}" | jq -r '.id // empty')"
if [[ -n "${GITOPS_ID}" ]]; then
  ok "Project exists (id ${GITOPS_ID})"
else
  GITOPS_ID="$(gl_api POST /projects --data "$(jq -nc --arg n "${GITOPS_PROJECT}" --argjson g "${GROUP_ID}" \
    '{name: $n, path: $n, namespace_id: $g, visibility: "public", initialize_with_readme: false,
      description: "Desired state of ocp-demo-app (Kustomize) — synced by OpenShift GitOps"}')" | jq -r '.id // empty')"
  [[ -n "${GITOPS_ID}" ]] || { warn "Could not create project '${GITOPS_PATH}'"; exit 1; }
  ok "Project created (id ${GITOPS_ID})"
fi
echo ""

step "Seed the manifests from ${GITOPS_SEED_DIR}/ — overlay pinned to the image running today"
show_cmd "# ${GITOPS_SEED_DIR}/overlays/dev/kustomization.yaml (rendered)
$(render "${GITOPS_SEED_DIR}/overlays/dev/kustomization.yaml")"
HAS_COMMITS="$(gl_api GET "/projects/${GITOPS_ID}/repository/commits?per_page=1" | jq -r 'if type == "array" then length else 0 end')"
if [[ "${HAS_COMMITS}" != "0" && "${GITOPS_RESEED:-0}" != "1" ]]; then
  ok "Repo already has commits — not re-seeding (GITOPS_RESEED=1 to overwrite the manifests)"
else
  ACTIONS="[]"
  while IFS= read -r f; do
    rel="${f#"${GITOPS_SEED_DIR}"/}"
    action=create
    [[ "${HAS_COMMITS}" != "0" ]] && \
      [[ "$(gl_api GET "/projects/${GITOPS_ID}/repository/files/${rel//\//%2F}?ref=main" | jq -r '.file_name // empty')" != "" ]] && action=update
    ACTIONS="$(jq -c --arg a "${action}" --arg p "${rel}" --arg c "$(render "${f}")" \
      '. + [{action: $a, file_path: $p, content: $c}]' <<< "${ACTIONS}")"
  done < <(find "${GITOPS_SEED_DIR}" -type f | sort)
  RESP="$(gl_api POST "/projects/${GITOPS_ID}/repository/commits" --data "$(jq -nc --argjson a "${ACTIONS}" \
    '{branch: "main", commit_message: "ocp-demo-app: initial desired state (dev)", actions: $a}')")"
  [[ -n "$(jq -r '.id // empty' <<< "${RESP}")" ]] || { warn "Seeding failed: ${RESP}"; exit 1; }
  ok "Seeded: $(jq -r '.id[0:8]' <<< "${RESP}")"
fi
gl_api GET "/projects/${GITOPS_ID}/repository/tree?recursive=true&per_page=50" \
  | jq -r '.[] | select(.type == "blob") | "    " + .path'
echo -e "  ${BOLD}Repo:${RESET} ${CYAN}${GITOPS_WEB}${RESET}"
echo ""
pause

step "Write access for the pipeline: project token '${GITOPS_TOKEN_NAME}' → Secret '${GITOPS_SECRET}' in ${CICD_PROJECT}"
show_cmd "POST ${GL_API}/projects/<id>/access_tokens  { name: ${GITOPS_TOKEN_NAME}, scopes: [read_repository, write_repository] }
oc create secret generic ${GITOPS_SECRET} -n ${CICD_PROJECT} \\
  --from-literal=username=<bot-user> --from-literal=password=<token>"
G_USER="$(oc get secret "${GITOPS_SECRET}" -n "${CICD_PROJECT}" -o jsonpath='{.data.username}' 2>/dev/null | base64 -d 2>/dev/null || true)"
G_TOKEN="$(oc get secret "${GITOPS_SECRET}" -n "${CICD_PROJECT}" -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || true)"
# repository-only scopes: /personal_access_tokens/self still answers 200 for a valid token
if [[ -n "${G_TOKEN}" && "$(curl -sk -o /dev/null -w '%{http_code}' -H "PRIVATE-TOKEN: ${G_TOKEN}" "${GL_API}/personal_access_tokens/self")" == "200" ]]; then
  ok "Reusing token of '${G_USER}'"
else
  for tid in $(gl_api GET "/projects/${GITOPS_ID}/access_tokens?state=active" \
                 | jq -r --arg n "${GITOPS_TOKEN_NAME}" '.[]? | select(.name == $n) | .id'); do
    gl_api DELETE "/projects/${GITOPS_ID}/access_tokens/${tid}" >/dev/null
  done
  TOKEN_JSON="$(gl_api POST "/projects/${GITOPS_ID}/access_tokens" --data "$(jq -nc \
    --arg n "${GITOPS_TOKEN_NAME}" --arg e "$(date -d '+364 days' +%F)" \
    '{name: $n, access_level: 40, expires_at: $e, scopes: ["read_repository", "write_repository"]}')")"
  G_TOKEN="$(jq -r '.token // empty' <<< "${TOKEN_JSON}")"
  G_USER="$(gl_api GET "/users/$(jq -r '.user_id' <<< "${TOKEN_JSON}")" | jq -r '.username // empty')"
  [[ -n "${G_TOKEN}" && -n "${G_USER}" ]] || { warn "Token creation failed"; exit 1; }
  ok "Token created for bot user '${G_USER}' (Maintainer, repository read/write only)"
fi
oc create secret generic "${GITOPS_SECRET}" -n "${CICD_PROJECT}" \
  --from-literal=username="${G_USER}" --from-literal=password="${G_TOKEN}" \
  --dry-run=client -o yaml | oc apply -f - >/dev/null
ok "Secret '${GITOPS_SECRET}' ready"
echo ""

step "Webhook: gitops repo → Argo CD (sync seconds after a commit instead of the 3-min poll)"
show_cmd "POST ${GL_API}/projects/<id>/hooks
  { url: ${ARGO_WEBHOOK_URL}, push_events: true }"
HOOK_BODY="$(jq -nc --arg u "${ARGO_WEBHOOK_URL}" '{url: $u, push_events: true, enable_ssl_verification: false}')"
HOOK_ID="$(gl_api GET "/projects/${GITOPS_ID}/hooks" | jq -r --arg u "${ARGO_WEBHOOK_URL}" '.[]? | select(.url == $u) | .id' | head -1)"
if [[ -n "${HOOK_ID}" ]]; then
  gl_api PUT "/projects/${GITOPS_ID}/hooks/${HOOK_ID}" --data "${HOOK_BODY}" >/dev/null; ok "Webhook updated"
else
  gl_api POST "/projects/${GITOPS_ID}/hooks" --data "${HOOK_BODY}" | jq -e '.id' >/dev/null && ok "Webhook created"
fi
echo ""
pause

# ─────────────────────────────────────────────────────────────────────────────
# PART 3 — Argo CD
# ─────────────────────────────────────────────────────────────────────────────
header "PART 3 — Argo CD: project, repository, application"

step "Allow the default Argo CD instance to manage '${DEV_PROJECT}'"
show_cmd "oc label namespace ${DEV_PROJECT} argocd.argoproj.io/managed-by=${ARGO_NAMESPACE} --overwrite"
oc label namespace "${DEV_PROJECT}" "argocd.argoproj.io/managed-by=${ARGO_NAMESPACE}" --overwrite >/dev/null
for _ in $(seq 1 30); do
  oc get rolebinding -n "${DEV_PROJECT}" -o name 2>/dev/null | grep -q "${ARGO_NAMESPACE}" && break
  sleep 2
done
ok "Operator granted the Argo CD controller access to '${DEV_PROJECT}' (RoleBinding $(oc get rolebinding -n "${DEV_PROJECT}" -o name | grep -m1 "${ARGO_NAMESPACE}" | cut -d/ -f2))"
echo ""

step "AppProject '${ARGO_PROJECT}' (allowed repo, destination, kinds) + repository"
show_cmd "$(render "${ARGO_DIR}/appproject.yaml")"
render "${ARGO_DIR}/appproject.yaml" | oc apply -f -
echo ""

step "Pipeline may read Applications (it waits for the sync in step 37)"
show_cmd "$(render "${ARGO_DIR}/rbac-pipeline.yaml" | grep -vE '^#')"
render "${ARGO_DIR}/rbac-pipeline.yaml" | oc apply -f -
echo ""
pause

PODS_BEFORE="$(oc get pods -n "${DEV_PROJECT}" -l "app=${APP_NAME}" -o jsonpath='{.items[*].metadata.name}')"
step "Application '${ARGO_APP}': ${GITOPS_OVERLAY} → ${DEV_PROJECT}, automated (prune + self-heal)"
show_cmd "$(render "${ARGO_DIR}/application.yaml")"
render "${ARGO_DIR}/application.yaml" | oc apply -f -
echo ""

step "Waiting for Argo CD to adopt the running app..."
for i in $(seq 1 60); do
  read -r SYNC HEALTH REV <<< "$(app_state)"
  [[ "${SYNC:-}" == "Synced" && "${HEALTH:-}" == "Healthy" ]] && break
  (( i % 4 == 0 )) && echo "  sync=${SYNC:-?} health=${HEALTH:-?}"
  sleep 5
done
read -r SYNC HEALTH REV <<< "$(app_state)"
[[ "${SYNC}" == "Synced" && "${HEALTH}" == "Healthy" ]] \
  && ok "Application ${ARGO_APP}: ${SYNC} / ${HEALTH} at ${REV:0:8}" \
  || warn "Application ${ARGO_APP}: sync=${SYNC} health=${HEALTH} — check the Argo CD UI"
echo ""
pause

# ─────────────────────────────────────────────────────────────────────────────
# PART 4 — What changed (and what did not)
# ─────────────────────────────────────────────────────────────────────────────
header "PART 4 — Argo CD now owns ${DEV_PROJECT}"

show_cmd "oc get application ${ARGO_APP} -n ${ARGO_NAMESPACE}
oc get pods -n ${DEV_PROJECT} -l app=${APP_NAME}"
oc get application "${ARGO_APP}" -n "${ARGO_NAMESPACE}"
echo ""
oc get application "${ARGO_APP}" -n "${ARGO_NAMESPACE}" \
  -o jsonpath='{range .status.resources[*]}  {.kind}/{.name}: {.status} {.health.status}{"\n"}{end}'
echo ""
PODS_AFTER="$(oc get pods -n "${DEV_PROJECT}" -l "app=${APP_NAME}" -o jsonpath='{.items[*].metadata.name}')"
oc get pods -n "${DEV_PROJECT}" -l "app=${APP_NAME}"
[[ "${PODS_BEFORE}" == "${PODS_AFTER}" ]] && ok "Same pod(s) as before — Git already described the running state, nothing was redeployed"
echo ""
ADMIN_PW_CMD="oc extract secret/openshift-gitops-cluster -n ${ARGO_NAMESPACE} --keys=admin.password --to=-"
echo -e "  ${BOLD}Argo CD UI     :${RESET} ${CYAN}${ARGO_URL}/applications/${ARGO_NAMESPACE}/${ARGO_APP}${RESET}"
echo -e "                   log in with OpenShift (cluster-admins → admin) or user 'admin': ${ADMIN_PW_CMD}"
echo -e "  ${BOLD}Console        :${RESET} ${CYAN}${CONSOLE_URL}/environments${RESET}  (Developer → Environments)"
echo -e "  ${BOLD}Gitops repo    :${RESET} ${CYAN}${GITOPS_WEB}${RESET}"
echo ""
cat <<'MSG'
  • The app tree in Argo CD: Application → Deployment → ReplicaSet → Pod, Service, Route
  • From now on: change Git, not the cluster. Step 37 lets the pipeline do exactly that.
MSG
echo ""
ok "Argo CD manages ${DEV_PROJECT} from ${GITOPS_PATH} (${GITOPS_OVERLAY})."
echo -e "  Next: ${CYAN}./scripts/37-pipeline-gitops.sh${RESET} — the pipeline delivers through Git."
echo ""

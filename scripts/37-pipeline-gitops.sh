#!/usr/bin/env bash
# =============================================================================
# 37-pipeline-gitops.sh — ACT 5: the pipeline delivers through Git (Argo CD)
#
#   1. Task 'gitops-update-image': clone the gitops repo, `kustomize edit set
#      image <repo>@<digest>`, commit, push, then WAIT until the Argo CD
#      Application is Synced + Healthy on that commit (synchronous CI/CD).
#   2. Switch delivery via Git: a commit to .tekton/push.yaml sets
#      deploy-mode=gitops → Pipelines-as-Code runs the pipeline → the image
#      reaches ocp-demo-dev through the gitops repo and Argo CD.
#   3. Least privilege: the pipeline no longer needs write access to the dev
#      project (edit role removed).
#
# Prerequisites: steps 32, 35 (Pipelines-as-Code), 36 (Argo CD Application).
# Idempotent: Task/Pipeline via `oc apply`; .tekton/ committed only if it
# differs (otherwise a run is started with tkn).
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/demo-config.sh"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="cicd/tekton/build"
PAC_DIR="cicd/tekton/pac"
cd "${REPO_ROOT}"

header "ACT 5 — CI → GitOps: the pipeline delivers through Git"

check_login
for bin in tkn jq curl envsubst; do
  command -v "${bin}" &>/dev/null || { warn "'${bin}' not found in PATH"; exit 1; }
done
argo_enabled || { warn "Argo CD Application '${ARGO_APP}' not found — run scripts/36-gitops-setup.sh first"; exit 1; }

GITLAB_URL="https://$(get_gitlab_host)"
GL_API="${GITLAB_URL}/api/v4"
ROOT_TOKEN="$(get_gitlab_cred root-token)"
PROJECT_PATH="${GITLAB_GROUP}/${GITLAB_PROJECT}"
PROJECT_ENC="${PROJECT_PATH//\//%2F}"
GITOPS_PATH="${GITLAB_GROUP}/${GITOPS_PROJECT}"
GITOPS_ENC="${GITOPS_PATH//\//%2F}"
ARGO_URL="https://$(oc get route openshift-gitops-server -n "${ARGO_NAMESPACE}" -o jsonpath='{.spec.host}')"
CONSOLE_URL="$(get_console_url)"

gl_api() {
  local method="$1" path="$2"; shift 2
  curl -sk -X "${method}" -H "PRIVATE-TOKEN: ${ROOT_TOKEN}" -H 'Content-Type: application/json' "${GL_API}${path}" "$@"
}
render_pac() {
  IMAGE_REPO="$(get_app_image_repo)" GITLAB_PROJECT_URL="${GITLAB_URL}/${PROJECT_PATH}" GITLAB_API_URL="${PAC_GITLAB_API_URL}" \
    DEPLOY_MODE="gitops" GITOPS_REPO_INTERNAL="$(get_gitops_repo_internal)" \
    envsubst '${APP_NAME} ${PIPELINE_NAME} ${CICD_PROJECT} ${DEV_PROJECT} ${IMAGE_REPO} ${MAVEN_CACHE_PVC} ${REGISTRY_SECRET} ${PAC_SECRET} ${GITLAB_PROJECT_URL} ${GITLAB_API_URL} ${DEPLOY_MODE} ${GITOPS_REPO_INTERNAL}' < "$1"
}
dev_image() { oc get deployment "${APP_NAME}" -n "${DEV_PROJECT}" -o jsonpath='{.spec.template.spec.containers[0].image}'; }
run_status() { oc get pipelinerun "$1" -n "${CICD_PROJECT}" -o jsonpath='{.status.conditions[0].reason}' 2>/dev/null; }

# ─────────────────────────────────────────────────────────────────────────────
# PART 1 — Concept
# ─────────────────────────────────────────────────────────────────────────────
header "PART 1 — CI writes to Git, Argo CD deploys"

cat <<'MSG'
   build-jar → build-image → acs-image-check → deploy-gitops
                                                  │ 1. kustomize edit set image <repo>@<digest>
                                                  │ 2. git commit + push   → gitops repo
                                                  │ 3. wait: Application Synced + Healthy
                                                  ▼
                                          Argo CD syncs ocp-demo-dev

  • Synchronous (deck: "CI directly commits image changes"): a green pipeline
    still means "running in dev" — but the deployment itself is done by Argo CD
  • The gitops repo history = deployment history (who, what, when, which image)
MSG
echo ""
pause

# ─────────────────────────────────────────────────────────────────────────────
# PART 2 — Task + Pipeline
# ─────────────────────────────────────────────────────────────────────────────
header "PART 2 — Task 'gitops-update-image'"

step "Update the manifest, push, wait for Argo CD"
show_cmd "# ${BUILD_DIR}/task-gitops-update-image.yaml
$(cat "${BUILD_DIR}/task-gitops-update-image.yaml")" \
  "Create Task 'gitops-update-image'" \
  "Console → Pipelines → Tasks → Create → Task (paste the YAML)"
oc apply -n "${CICD_PROJECT}" -f "${BUILD_DIR}/task-gitops-update-image.yaml"
echo ""
pause

step "Pipeline: deploy-dev (oc) or deploy-gitops — chosen by the 'deploy-mode' parameter"
show_cmd "$(sed -n '/- name: deploy-mode/,/argo-app/p' "${BUILD_DIR}/pipeline-build-deploy.yaml")
...
$(sed -n '/- name: deploy-gitops/,$p' "${BUILD_DIR}/pipeline-build-deploy.yaml")" \
  "Update Pipeline '${PIPELINE_NAME}'" \
  "Console → Pipelines → ${PIPELINE_NAME} → Actions → Edit Pipeline (builder or YAML view)"
oc apply -n "${CICD_PROJECT}" -f "${BUILD_DIR}/pipeline-build-deploy.yaml"
echo ""
pause

# ─────────────────────────────────────────────────────────────────────────────
# PART 3 — Switch delivery through Git
# ─────────────────────────────────────────────────────────────────────────────
header "PART 3 — Switch the app to GitOps delivery (a commit, of course)"

GITOPS_BEFORE="$(gl_api GET "/projects/${GITOPS_ENC}/repository/commits/main" | jq -r '.id')"
IMAGE_BEFORE="$(dev_image)"
NEW_PUSH="$(render_pac "${PAC_DIR}/push.yaml")"
CUR_PUSH="$(gl_api GET "/projects/${PROJECT_ENC}/repository/files/.tekton%2Fpush.yaml/raw?ref=main")"

step ".tekton/push.yaml in the app repo: deploy-mode oc → gitops"
show_cmd "$(diff <(echo "${CUR_PUSH}") <(echo "${NEW_PUSH}") || true)" \
  "Commit a change to .tekton/push.yaml (main)" \
  "GitLab → ${PROJECT_PATH} → Code → Repository → .tekton/push.yaml → Edit → Commit changes"
if pac_enabled && [[ "${CUR_PUSH}" != "${NEW_PUSH}" ]]; then
  ACTION=update; [[ "${CUR_PUSH}" == *'"message":"404'* ]] && ACTION=create
  RESP="$(gl_api POST "/projects/${PROJECT_ENC}/repository/commits" --data "$(jq -nc --arg a "${ACTION}" --arg c "${NEW_PUSH}" \
    '{branch: "main", commit_message: "Deliver through GitOps (Argo CD)", actions: [{action: $a, file_path: ".tekton/push.yaml", content: $c}]}')")"
  SHA="$(jq -r '.id // empty' <<< "${RESP}")"
  [[ -n "${SHA}" ]] || { warn "Commit failed: ${RESP}"; exit 1; }
  ok "Committed ${SHA:0:8} — the push triggers the pipeline (Pipelines-as-Code)"
  echo -e "  ${BOLD}Watch:${RESET} ${CYAN}${CONSOLE_URL}/k8s/ns/${CICD_PROJECT}/tekton.dev~v1~PipelineRun${RESET}   ${CYAN}${ARGO_URL}/applications/${ARGO_NAMESPACE}/${ARGO_APP}${RESET}"
  echo ""
  wait_pac_run "${SHA}"
  RUN="${PAC_RUN}"
else
  ok ".tekton/push.yaml already uses deploy-mode=gitops (or Pipelines-as-Code not connected) — starting a run with tkn"
  show_cmd "tkn pipeline start ${PIPELINE_NAME} -n ${CICD_PROJECT} ... -p deploy-mode=gitops --showlog" \
    "Start a PipelineRun (deploy-mode=gitops)" \
    "Console → Pipelines → ${PIPELINE_NAME} → Actions → Start (deploy-mode = gitops)"
  start_build_run
  RUN="$(last_build_run)"
fi
echo ""
STATUS="$(run_status "${RUN}")"
run_succeeded "${RUN}" && ok "PipelineRun '${RUN}': Succeeded — delivered by Argo CD" \
  || { warn "PipelineRun '${RUN}': ${STATUS}"; exit 1; }
echo ""
pause

# ─────────────────────────────────────────────────────────────────────────────
# PART 4 — Follow the change
# ─────────────────────────────────────────────────────────────────────────────
header "PART 4 — Follow the image: pipeline → Git → Argo CD → cluster"

GITOPS_AFTER="$(gl_api GET "/projects/${GITOPS_ENC}/repository/commits/main" | jq -r '.id')"
step "New commit in the gitops repo (by the pipeline)"
show_cmd "GET ${GL_API}/projects/${GITOPS_ENC}/repository/commits/${GITOPS_AFTER:0:8}/diff" \
  "Read the gitops commit (diff)" \
  "GitLab → ${GITOPS_PATH} → Code → Commits → ${GITOPS_AFTER:0:8} → Changes
${GITLAB_URL}/${GITOPS_PATH}/-/commit/${GITOPS_AFTER}"
gl_api GET "/projects/${GITOPS_ENC}/repository/commits/${GITOPS_AFTER}" | jq -r '"  \(.short_id)  \(.author_name)  \(.title)"'
gl_api GET "/projects/${GITOPS_ENC}/repository/commits/${GITOPS_AFTER}/diff" \
  | jq -r '.[] | "  --- " + .new_path, (.diff | split("\n")[] | select(test("^[-+][^-+]")) | "    " + .)'
echo -e "  ${BOLD}Gitops repo:${RESET} ${CYAN}${GITLAB_URL}/${GITOPS_PATH}/-/commit/${GITOPS_AFTER}${RESET}"
[[ "${GITOPS_AFTER}" != "${GITOPS_BEFORE}" ]] || warn "No new gitops commit (image unchanged?)"
echo ""

step "Argo CD Application and the running image"
show_cmd "oc get application ${ARGO_APP} -n ${ARGO_NAMESPACE}
oc get deployment ${APP_NAME} -n ${DEV_PROJECT} -o jsonpath='{.spec.template.spec.containers[0].image}'" \
  "Inspect the Application + running image" \
  "Argo CD → Applications → ${ARGO_APP} → App details / History and rollback
Console → Workloads → Deployments → ${APP_NAME} → YAML (image)"
oc get application "${ARGO_APP}" -n "${ARGO_NAMESPACE}" \
  -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REVISION:.status.sync.revision'
echo -e "  Before : ${CYAN}${IMAGE_BEFORE}${RESET}"
echo -e "  Now    : ${CYAN}$(dev_image)${RESET}"
echo -e "  Deploy history in Argo CD: $(oc get application "${ARGO_APP}" -n "${ARGO_NAMESPACE}" -o jsonpath='{.status.history}' | jq 'length') sync(s)"
echo ""
pause

# ─────────────────────────────────────────────────────────────────────────────
# PART 5 — Least privilege
# ─────────────────────────────────────────────────────────────────────────────
header "PART 5 — The pipeline no longer needs the keys to dev"

step "Remove the pipeline's edit role in '${DEV_PROJECT}' (granted in step 32 for oc deploys)"
show_cmd "oc policy remove-role-from-user edit system:serviceaccount:${CICD_PROJECT}:pipeline -n ${DEV_PROJECT}" \
  "Remove the pipeline SA's edit role" \
  "Console → User Management → RoleBindings (project ${DEV_PROJECT}) → edit binding of 'pipeline' → Delete"
oc policy remove-role-from-user edit "system:serviceaccount:${CICD_PROJECT}:pipeline" -n "${DEV_PROJECT}" &>/dev/null || true
echo -e "  can-i update deployments in ${DEV_PROJECT}: ${BOLD}$(oc auth can-i update deployments -n "${DEV_PROJECT}" --as="system:serviceaccount:${CICD_PROJECT}:pipeline" || true)${RESET}"
echo -e "  can-i get applications in ${ARGO_NAMESPACE}: ${BOLD}$(oc auth can-i get applications.argoproj.io -n "${ARGO_NAMESPACE}" --as="system:serviceaccount:${CICD_PROJECT}:pipeline" || true)${RESET}"
echo ""
cat <<'MSG'
  CI can write to Git and read the Application status — nothing more.
  Only Argo CD (in the cluster) changes ocp-demo-dev.
MSG
echo ""
ok "Delivery is GitOps: every push to main ends as a commit in the gitops repo, synced by Argo CD."
echo -e "  Next: ${CYAN}./scripts/38-gitops-drift-rollback.sh${RESET} — self-heal and rollback with git revert."
echo ""

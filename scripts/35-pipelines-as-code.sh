#!/usr/bin/env bash
# =============================================================================
# 35-pipelines-as-code.sh — ACT 5: Pipelines-as-Code with GitLab
#
#   1. Connect GitLab ↔ OpenShift Pipelines: Secret (GitLab token + webhook
#      secret), Repository CR, GitLab project webhook.
#   2. Add .tekton/ (push + merge-request PipelineRuns) to the app repo →
#      the commit itself triggers the first automatic run (build → deploy).
#   3. Shift left: a merge request adds log4j → the MR run fails at the ACS
#      gate and GitLab shows it on the MR *before* merge → MR closed.
#
# Prerequisites: steps 30, 32 (pipeline, secrets, Maven cache), ideally 34.
# Idempotent: Secret/Repository via `oc apply`, webhook upserted, .tekton/
# committed only when it differs, the demo MR/branch is recreated each run.
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/demo-config.sh"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PAC_DIR="cicd/tekton/pac"
cd "${REPO_ROOT}"

header "ACT 5 — Pipelines-as-Code (GitLab)"

check_login
for bin in tkn jq curl envsubst; do
  command -v "${bin}" &>/dev/null || { warn "'${bin}' not found in PATH"; exit 1; }
done
oc get pipeline "${PIPELINE_NAME}" -n "${CICD_PROJECT}" &>/dev/null || \
  { warn "Pipeline '${PIPELINE_NAME}' not found — run scripts/32-pipeline-build-deploy.sh first"; exit 1; }

GITLAB_URL="https://$(get_gitlab_host)"
GL_API="${GITLAB_URL}/api/v4"
ROOT_TOKEN="$(get_gitlab_cred root-token)"
CI_TOKEN="$(get_gitlab_cred ci-token)"
[[ -n "${ROOT_TOKEN}" && -n "${CI_TOKEN}" ]] || { warn "GitLab tokens not found — run scripts/30-gitlab-setup.sh"; exit 1; }
PROJECT_PATH="${GITLAB_GROUP}/${GITLAB_PROJECT}"
PROJECT_ENC="${PROJECT_PATH//\//%2F}"
PROJECT_URL="${GITLAB_URL}/${PROJECT_PATH}"
CONSOLE_URL="$(get_console_url)"

gl_api() {
  local method="$1" path="$2"; shift 2
  curl -sk -X "${method}" -H "PRIVATE-TOKEN: ${ROOT_TOKEN}" -H 'Content-Type: application/json' "${GL_API}${path}" "$@"
}
render() {
  IMAGE_REPO="$(get_app_image_repo)" GITLAB_PROJECT_URL="${PROJECT_URL}" GITLAB_API_URL="${PAC_GITLAB_API_URL}" \
    DEPLOY_MODE="${DEPLOY_MODE:-$(get_deploy_mode)}" GITOPS_REPO_INTERNAL="$(get_gitops_repo_internal)" \
    envsubst '${APP_NAME} ${PIPELINE_NAME} ${CICD_PROJECT} ${DEV_PROJECT} ${IMAGE_REPO} ${MAVEN_CACHE_PVC} ${REGISTRY_SECRET} ${PAC_SECRET} ${GITLAB_PROJECT_URL} ${GITLAB_API_URL} ${DEPLOY_MODE} ${GITOPS_REPO_INTERNAL}' < "$1"
}
run_status() { oc get pipelinerun "$1" -n "${CICD_PROJECT}" -o jsonpath='{.status.conditions[0].reason}' 2>/dev/null; }
commit_statuses() {
  gl_api GET "/projects/${PROJECT_ENC}/repository/commits/$1/statuses" \
    | jq -r '.[]? | "    \(.name)  →  \(.status)"' | sort -u
}

# ─────────────────────────────────────────────────────────────────────────────
# PART 1 — Concept
# ─────────────────────────────────────────────────────────────────────────────
header "PART 1 — Pipelines live with the code"

cat <<'MSG'
   git push / merge request
        │  webhook
        ▼
   GitLab ───────────► Pipelines-as-Code controller (openshift-pipelines)
        ▲                    │ reads .tekton/*.yaml from the commit
        │ commit status      ▼
        └──────────── PipelineRun in ocp-demo-cicd (build-deploy)

  • The app team owns WHEN and WITH WHAT parameters (.tekton/ in their repo)
  • The platform team owns HOW (Pipeline 'build-deploy' in the CI namespace)
  • Results go back to GitLab: commit / merge request status, /retest comments
MSG
echo ""
pause

# ─────────────────────────────────────────────────────────────────────────────
# PART 2 — Connect GitLab and OpenShift Pipelines
# ─────────────────────────────────────────────────────────────────────────────
header "PART 2 — Connect GitLab and OpenShift Pipelines"

WEBHOOK_SECRET="$(oc get secret "${PAC_SECRET}" -n "${CICD_PROJECT}" -o jsonpath='{.data.webhook\.secret}' 2>/dev/null | base64 -d 2>/dev/null || true)"
[[ -n "${WEBHOOK_SECRET}" ]] || WEBHOOK_SECRET="$(head -c 96 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | cut -c1-32)"

step "Secret '${PAC_SECRET}': GitLab API token (project token '${GITLAB_CI_TOKEN_NAME}') + webhook secret"
show_cmd "oc create secret generic ${PAC_SECRET} -n ${CICD_PROJECT} \\
  --from-literal=provider.token=<gitlab-ci-token> \\
  --from-literal=webhook.secret=<random>"
oc create secret generic "${PAC_SECRET}" -n "${CICD_PROJECT}" \
  --from-literal=provider.token="${CI_TOKEN}" --from-literal=webhook.secret="${WEBHOOK_SECRET}" \
  --dry-run=client -o yaml | oc apply -f - >/dev/null
ok "Secret '${PAC_SECRET}' ready"
echo ""

step "Repository CR: this GitLab project → PipelineRuns in '${CICD_PROJECT}'"
show_cmd "$(render "${PAC_DIR}/repository.yaml")"
render "${PAC_DIR}/repository.yaml" | oc apply -f -
echo ""
pause

step "GitLab project webhook → PAC controller (push, merge request, comment events)"
show_cmd "POST ${GL_API}/projects/${PROJECT_ENC}/hooks
  { url: ${PAC_WEBHOOK_URL},
    token: <webhook-secret>, push_events, merge_requests_events, note_events }"
HOOK_BODY="$(jq -nc --arg u "${PAC_WEBHOOK_URL}" --arg t "${WEBHOOK_SECRET}" '{
  url: $u, token: $t, push_events: true, merge_requests_events: true, note_events: true,
  tag_push_events: false, enable_ssl_verification: false}')"
HOOK_ID="$(gl_api GET "/projects/${PROJECT_ENC}/hooks" | jq -r --arg u "${PAC_WEBHOOK_URL}" '.[]? | select(.url == $u) | .id' | head -1)"
if [[ -n "${HOOK_ID}" ]]; then
  gl_api PUT "/projects/${PROJECT_ENC}/hooks/${HOOK_ID}" --data "${HOOK_BODY}" >/dev/null
  ok "Webhook updated (id ${HOOK_ID})"
else
  HOOK_ID="$(gl_api POST "/projects/${PROJECT_ENC}/hooks" --data "${HOOK_BODY}" | jq -r '.id // empty')"
  [[ -n "${HOOK_ID}" ]] || { warn "Webhook creation failed"; exit 1; }
  ok "Webhook created (id ${HOOK_ID})"
fi
echo -e "  ${BOLD}GitLab → Settings → Webhooks:${RESET} ${CYAN}${PROJECT_URL}/-/hooks${RESET}"
echo -e "  Both directions use in-cluster Services: no public endpoint, no self-signed certificate issues."
echo ""
pause

# ─────────────────────────────────────────────────────────────────────────────
# PART 3 — .tekton/ in the app repo: the commit triggers the first run
# ─────────────────────────────────────────────────────────────────────────────
header "PART 3 — Add .tekton/ to the app repo"

step ".tekton/push.yaml — on push to main: build, scan, deploy"
show_cmd "$(render "${PAC_DIR}/push.yaml")"
step ".tekton/pull-request.yaml — on merge request to main: build + scan, deploy-mode=none"
show_cmd "$(render "${PAC_DIR}/pull-request.yaml" | grep -E 'on-event|deploy|generateName|pipelineRef|name: build')
  ... (same workspaces as push.yaml)"

ACTIONS="[]"
for f in push pull-request; do
  CONTENT="$(render "${PAC_DIR}/${f}.yaml")"
  CURRENT="$(gl_api GET "/projects/${PROJECT_ENC}/repository/files/.tekton%2F${f}.yaml/raw?ref=main")"
  if [[ "${CURRENT}" == *'"message":"404'* ]]; then ACTION=create
  elif [[ "${CURRENT}" == "${CONTENT}" ]]; then continue
  else ACTION=update; fi
  ACTIONS="$(jq -c --arg a "${ACTION}" --arg p ".tekton/${f}.yaml" --arg c "${CONTENT}" \
    '. + [{action: $a, file_path: $p, content: $c}]' <<< "${ACTIONS}")"
done
step "Commit .tekton/ to main — this push is the first event Pipelines-as-Code reacts to"
show_cmd "POST ${GL_API}/projects/${PROJECT_ENC}/repository/commits
  { branch: main, commit_message: \"Add Pipelines-as-Code PipelineRuns\",
    actions: [ .tekton/push.yaml, .tekton/pull-request.yaml ] }"
if [[ "${ACTIONS}" == "[]" ]]; then
  ok ".tekton/ already up to date on main — no commit, no new run"
  PUSH_RUN=""
else
  RESP="$(gl_api POST "/projects/${PROJECT_ENC}/repository/commits" --data "$(jq -nc --argjson a "${ACTIONS}" \
    '{branch: "main", commit_message: "Add Pipelines-as-Code PipelineRuns", actions: $a}')")"
  PUSH_SHA="$(jq -r '.id // empty' <<< "${RESP}")"
  [[ -n "${PUSH_SHA}" ]] || { warn "Commit failed: ${RESP}"; exit 1; }
  ok "Committed ${PUSH_SHA:0:8}: ${PROJECT_URL}/-/commit/${PUSH_SHA}"
  echo -e "  ${BOLD}Watch:${RESET} ${CYAN}${CONSOLE_URL}/k8s/ns/${CICD_PROJECT}/tekton.dev~v1~PipelineRun${RESET}"
  echo ""
  wait_pac_run "${PUSH_SHA}"
  PUSH_RUN="${PAC_RUN}"
  echo ""
  run_succeeded "${PUSH_RUN}" && ok "PipelineRun '${PUSH_RUN}' (push): Succeeded — deployed" \
    || warn "PipelineRun '${PUSH_RUN}' (push): $(run_status "${PUSH_RUN}")"
  echo ""
  step "Status reported back to GitLab on the commit"
  show_cmd "GET ${GL_API}/projects/${PROJECT_ENC}/repository/commits/${PUSH_SHA:0:8}/statuses"
  commit_statuses "${PUSH_SHA}"
  echo -e "  ${BOLD}GitLab:${RESET} ${CYAN}${PROJECT_URL}/-/commit/${PUSH_SHA}${RESET}  (pipeline status icon)"
fi
echo ""
pause

# ─────────────────────────────────────────────────────────────────────────────
# PART 4 — Shift left: the ACS gate on a merge request
# ─────────────────────────────────────────────────────────────────────────────
header "PART 4 — Merge request: the gate runs BEFORE merge"

BRANCH_ENC="${PAC_MR_BRANCH//\//%2F}"
for iid in $(gl_api GET "/projects/${PROJECT_ENC}/merge_requests?state=opened&source_branch=${BRANCH_ENC}" | jq -r '.[]?.iid'); do
  gl_api PUT "/projects/${PROJECT_ENC}/merge_requests/${iid}" --data '{"state_event":"close"}' >/dev/null
done
gl_api DELETE "/projects/${PROJECT_ENC}/repository/branches/${BRANCH_ENC}" >/dev/null

step "Developer works on branch '${PAC_MR_BRANCH}': adds ${VULN_DEP_ARTIFACT} ${VULN_DEP_VERSION} (as in step 34)"
show_cmd "POST .../repository/branches   { branch: ${PAC_MR_BRANCH}, ref: main }
PUT  .../repository/files/pom.xml { branch: ${PAC_MR_BRANCH}, commit_message: \"${VULN_COMMIT_MSG}\" }
POST .../merge_requests           { source_branch: ${PAC_MR_BRANCH}, target_branch: main,
                                    title: \"${PAC_MR_TITLE}\" }"
gl_api POST "/projects/${PROJECT_ENC}/repository/branches?branch=${BRANCH_ENC}&ref=main" >/dev/null
POM="$(gl_api GET "/projects/${PROJECT_ENC}/repository/files/pom.xml/raw?ref=${BRANCH_ENC}")"
ANCHOR="<!-- OpenAPI / Swagger UI -->"
grep -q "${ANCHOR}" <<< "${POM}" || { warn "Anchor '${ANCHOR}' not found in pom.xml"; exit 1; }
DEP_XML="    <!-- File logging -->
    <dependency>
      <groupId>${VULN_DEP_GROUP}</groupId>
      <artifactId>${VULN_DEP_ARTIFACT}</artifactId>
      <version>${VULN_DEP_VERSION}</version>
    </dependency>
"
NEW_POM="$(DEP="${DEP_XML}" ANCHOR="${ANCHOR}" awk '
  index($0, ENVIRON["ANCHOR"]) && !done { printf "%s\n", ENVIRON["DEP"]; done=1 } { print }' <<< "${POM}")"
gl_api PUT "/projects/${PROJECT_ENC}/repository/files/pom.xml" --data "$(jq -nc \
  --arg b "${PAC_MR_BRANCH}" --arg c "${NEW_POM}" --arg m "${VULN_COMMIT_MSG}" \
  --arg an "${VULN_COMMIT_AUTHOR}" --arg ae "${VULN_COMMIT_EMAIL}" \
  '{branch: $b, content: $c, commit_message: $m, author_name: $an, author_email: $ae}')" >/dev/null
MR="$(gl_api POST "/projects/${PROJECT_ENC}/merge_requests" --data "$(jq -nc \
  --arg s "${PAC_MR_BRANCH}" --arg t "${PAC_MR_TITLE}" \
  '{source_branch: $s, target_branch: "main", title: $t, remove_source_branch: true}')")"
MR_IID="$(jq -r '.iid // empty' <<< "${MR}")"
MR_SHA="$(jq -r '.sha // empty' <<< "${MR}")"
[[ -n "${MR_IID}" && -n "${MR_SHA}" ]] || { warn "Merge request creation failed: ${MR}"; exit 1; }
ok "Merge request !${MR_IID}: ${PROJECT_URL}/-/merge_requests/${MR_IID}"
echo ""
wait_pac_run "${MR_SHA}"
MR_RUN="${PAC_RUN}"
echo ""
echo -e "  PipelineRun ${CYAN}${MR_RUN}${RESET} (merge request): ${BOLD}$(run_status "${MR_RUN}")${RESET}"
echo ""
pause

step "What the reviewer sees on the merge request"
show_cmd "GET ${GL_API}/projects/${PROJECT_ENC}/merge_requests/${MR_IID}
GET ${GL_API}/projects/${PROJECT_ENC}/repository/commits/${MR_SHA:0:8}/statuses"
commit_statuses "${MR_SHA}"
echo -e "  ${BOLD}Merge request:${RESET} ${CYAN}${PROJECT_URL}/-/merge_requests/${MR_IID}${RESET}"
echo -e "  ${BOLD}Dev still runs:${RESET} ${CYAN}$(oc get deployment "${APP_NAME}" -n "${DEV_PROJECT}" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)${RESET}"
echo ""
cat <<'MSG'
  The vulnerable change never reached main: the reviewer sees a failed pipeline
  on the MR, with a link to the PipelineRun and the ACS findings.
  (Comment "/retest" on the MR to run it again after pushing a fix.)
MSG
echo ""
pause

step "Close the merge request (the developer will pick a safe logging library)"
show_cmd "PUT ${GL_API}/projects/${PROJECT_ENC}/merge_requests/${MR_IID}  { state_event: close }
DELETE ${GL_API}/projects/${PROJECT_ENC}/repository/branches/${BRANCH_ENC}"
gl_api PUT "/projects/${PROJECT_ENC}/merge_requests/${MR_IID}" --data '{"state_event":"close"}' >/dev/null
gl_api DELETE "/projects/${PROJECT_ENC}/repository/branches/${BRANCH_ENC}" >/dev/null
ok "Merge request !${MR_IID} closed, branch '${PAC_MR_BRANCH}' deleted"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# PART 5 — Recap
# ─────────────────────────────────────────────────────────────────────────────
header "PART 5 — Recap"

show_cmd "oc get repository ${APP_NAME} -n ${CICD_PROJECT}
tkn pipelinerun list -n ${CICD_PROJECT} --limit 4"
oc get repositories.pipelinesascode.tekton.dev "${APP_NAME}" -n "${CICD_PROJECT}"
echo ""
tkn pipelinerun list -n "${CICD_PROJECT}" --limit 4
echo ""
cat <<'MSG'
  • No `tkn pipeline start` any more: Git events drive the pipeline
  • Push to main → build, scan, deploy · Merge request → build + scan, verdict on the MR
  • Next (GitOps): the pipeline stops deploying itself — it updates a manifest
    repo and Argo CD syncs the cluster
MSG
echo ""
ok "Pipelines-as-Code connected: GitLab events → OpenShift Pipelines → status in GitLab."
echo ""

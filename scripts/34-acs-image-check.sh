#!/usr/bin/env bash
# =============================================================================
# 34-acs-image-check.sh — ACT 5: DevSecOps gate with Red Hat ACS
#
# 1. Show the build-time policy that guards the pipeline (ACS_GATE_POLICY).
# 2. A developer commits a vulnerable dependency (log4j-core 2.14.1 —
#    Log4Shell) to GitLab.
# 3. The pipeline builds and pushes the image, ACS finds the CVE and
#    `roxctl image check` FAILS → deploy-dev never runs; dev keeps the good image.
# 4. The commit is reverted → the pipeline passes and deploys again.
#
# Prerequisite: scripts/32-pipeline-build-deploy.sh (pipeline, secrets, app).
# Idempotent: the vulnerable commit is only made if the dependency is absent,
# the revert only if it is present; every run starts new PipelineRuns.
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/demo-config.sh"

header "ACT 5 — DevSecOps: ACS gate in the pipeline"

check_login
for bin in tkn jq curl; do
  command -v "${bin}" &>/dev/null || { warn "'${bin}' not found in PATH"; exit 1; }
done

GITLAB_URL="https://$(get_gitlab_host)"
GL_API="${GITLAB_URL}/api/v4"
ROOT_TOKEN="$(get_gitlab_cred root-token)"
ACS_TOKEN="$(get_key "${ACS_TOKEN_KEY}")"
[[ -n "${ROOT_TOKEN}" ]] || { warn "GitLab root token not found — run scripts/30-gitlab-setup.sh"; exit 1; }
[[ -n "${ACS_TOKEN}" ]] || { warn "ACS API token not found: add '${ACS_TOKEN_KEY}:<token>' to ${KEYS_FILE}"; exit 1; }
[[ -n "${ACS_CENTRAL_URL}" ]] || { warn "ACS Central URL not found: add '${ACS_URL_KEY}:https://<central>' to ${KEYS_FILE}"; exit 1; }
oc get pipeline "${PIPELINE_NAME}" -n "${CICD_PROJECT}" &>/dev/null || \
  { warn "Pipeline '${PIPELINE_NAME}' not found — run scripts/32-pipeline-build-deploy.sh first"; exit 1; }

PROJECT_PATH="${GITLAB_GROUP}/${GITLAB_PROJECT}"
PROJECT_ENC="${PROJECT_PATH//\//%2F}"
VULN_DEP="${VULN_DEP_GROUP}:${VULN_DEP_ARTIFACT}:${VULN_DEP_VERSION}"
CONSOLE_URL="$(get_console_url)"

gl_api() {
  local method="$1" path="$2"; shift 2
  curl -sk -X "${method}" -H "PRIVATE-TOKEN: ${ROOT_TOKEN}" -H 'Content-Type: application/json' "${GL_API}${path}" "$@"
}
rox_api() { curl -sk -H "Authorization: Bearer ${ACS_TOKEN}" "${ACS_CENTRAL_URL}$1"; }
pom_on_main() { gl_api GET "/projects/${PROJECT_ENC}/repository/files/pom.xml/raw?ref=main"; }
dev_image() { oc get deployment "${APP_NAME}" -n "${DEV_PROJECT}" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null; }
dev_commit() { oc get deployment "${APP_NAME}" -n "${DEV_PROJECT}" -o jsonpath='{.metadata.annotations.ked-demo/git-commit}' 2>/dev/null; }
run_status() { oc get pipelinerun "$1" -n "${CICD_PROJECT}" -o jsonpath='{.status.conditions[0].reason}'; }
task_status() {
  oc get taskrun -n "${CICD_PROJECT}" -l "tekton.dev/pipelineRun=$1,tekton.dev/pipelineTask=$2" \
    -o jsonpath='{.items[0].status.conditions[0].reason}' 2>/dev/null || true
}

# ─────────────────────────────────────────────────────────────────────────────
# PART 1 — The gate
# ─────────────────────────────────────────────────────────────────────────────
header "PART 1 — The policy that guards the pipeline"

cat <<'MSG'
  Shift left: ACS evaluates policies at three lifecycle stages
    BUILD   → roxctl image check in the pipeline   ← this step
    DEPLOY  → admission controller in the cluster
    RUNTIME → process / network behaviour of running pods

  A policy with "enforcement" at BUILD makes `roxctl image check` exit non-zero,
  so the Tekton task — and the whole pipeline — fails before anything is deployed.
MSG
echo ""
pause

step "ACS policy '${ACS_GATE_POLICY}' (Central API)"
show_cmd "curl -H 'Authorization: Bearer <acs-api-token>' ${ACS_CENTRAL_URL}/v1/policies/<id> \\
  | jq '{name, lifecycleStages, enforcementActions, criteria}'"
POLICY_ID="$(rox_api /v1/policies | jq -r --arg n "${ACS_GATE_POLICY}" '.policies[]? | select(.name == $n) | .id' | head -1)"
[[ -n "${POLICY_ID}" ]] || { warn "Policy '${ACS_GATE_POLICY}' not found on Central"; exit 1; }
POLICY="$(rox_api "/v1/policies/${POLICY_ID}")"
jq '{name, severity, lifecycleStages, enforcementActions,
     criteria: [.policySections[].policyGroups[] | {(.fieldName): [.values[].value]}]}' <<< "${POLICY}"
if jq -e '.enforcementActions | index("FAIL_BUILD_ENFORCEMENT")' <<< "${POLICY}" >/dev/null; then
  ok "Enforced at BUILD: any fixable CVE of severity Important or higher fails the pipeline"
else
  warn "Policy is NOT enforced at build time — the pipeline will report but not fail"
fi
echo -e "  ${BOLD}Policy in ACS UI:${RESET} ${CYAN}${ACS_CENTRAL_URL}/main/policy-management/policies/${POLICY_ID}${RESET}"
echo ""
echo -e "  Currently deployed in ${DEV_PROJECT}: ${CYAN}$(dev_image)${RESET}"
echo -e "  from commit                     : ${CYAN}$(dev_commit)${RESET}"
GOOD_IMAGE="$(dev_image)"
echo ""
pause

# ─────────────────────────────────────────────────────────────────────────────
# PART 2 — A developer adds a vulnerable dependency
# ─────────────────────────────────────────────────────────────────────────────
header "PART 2 — A developer adds ${VULN_DEP_ARTIFACT} ${VULN_DEP_VERSION}"

DEP_XML="    <!-- File logging -->
    <dependency>
      <groupId>${VULN_DEP_GROUP}</groupId>
      <artifactId>${VULN_DEP_ARTIFACT}</artifactId>
      <version>${VULN_DEP_VERSION}</version>
    </dependency>
"
step "Commit to 'main' in GitLab (as '${VULN_COMMIT_AUTHOR}') — pom.xml gets:"
show_cmd "${DEP_XML}
→ PUT ${GL_API}/projects/${PROJECT_ENC}/repository/files/pom.xml
  { branch: main, commit_message: \"${VULN_COMMIT_MSG}\", content: <new pom.xml> }"
POM="$(pom_on_main)"
BAD_COMMITTED=false
if grep -q "<artifactId>${VULN_DEP_ARTIFACT}</artifactId>" <<< "${POM}"; then
  ok "pom.xml on main already contains ${VULN_DEP_ARTIFACT} — not committing again"
else
  ANCHOR="<!-- OpenAPI / Swagger UI -->"
  grep -q "${ANCHOR}" <<< "${POM}" || { warn "Anchor '${ANCHOR}' not found in pom.xml"; exit 1; }
  NEW_POM="$(DEP="${DEP_XML}" ANCHOR="${ANCHOR}" awk '
    index($0, ENVIRON["ANCHOR"]) && !done { printf "%s\n", ENVIRON["DEP"]; done=1 } { print }' <<< "${POM}")"
  RESP="$(gl_api PUT "/projects/${PROJECT_ENC}/repository/files/pom.xml" --data "$(jq -nc \
    --arg c "${NEW_POM}" --arg m "${VULN_COMMIT_MSG}" --arg an "${VULN_COMMIT_AUTHOR}" --arg ae "${VULN_COMMIT_EMAIL}" \
    '{branch: "main", content: $c, commit_message: $m, author_name: $an, author_email: $ae}')")"
  jq -e '.file_path' <<< "${RESP}" >/dev/null || { warn "Commit failed: ${RESP}"; exit 1; }
  ok "Committed '${VULN_COMMIT_MSG}'"
  BAD_COMMITTED=true
fi
BAD_SHA="$(gl_api GET "/projects/${PROJECT_ENC}/repository/commits?ref_name=main&path=pom.xml&per_page=20" \
  | jq -r --arg m "${VULN_COMMIT_MSG}" '[.[] | select(.title == $m)][0].id // empty')"
echo -e "  ${BOLD}Commit:${RESET} ${CYAN}${GITLAB_URL}/${PROJECT_PATH}/-/commit/${BAD_SHA}${RESET}"
echo ""
pause

# ─────────────────────────────────────────────────────────────────────────────
# PART 3 — The pipeline stops at the ACS gate
# ─────────────────────────────────────────────────────────────────────────────
header "PART 3 — Run the pipeline: the gate closes"

echo -e "  ${BOLD}PipelineRuns:${RESET} ${CYAN}${CONSOLE_URL}/k8s/ns/${CICD_PROJECT}/tekton.dev~v1~PipelineRun${RESET}"
if [[ "${BAD_COMMITTED}" == true ]] && pac_enabled; then
  step "Pipelines-as-Code is connected (step 35): the push already started the pipeline"
  show_cmd "oc get pipelinerun -n ${CICD_PROJECT} -l pipelinesascode.tekton.dev/sha=${BAD_SHA:0:8}..."
  wait_pac_run "${BAD_SHA}"
  BAD_RUN="${PAC_RUN}"
else
  step "Same pipeline as step 32 (with Pipelines-as-Code — step 35 — the push alone starts it)"
  show_cmd "tkn pipeline start ${PIPELINE_NAME} -n ${CICD_PROJECT} ... --showlog   # parameters/workspaces as in step 32"
  start_build_run
  BAD_RUN="$(last_build_run)"
fi
echo ""
echo -e "  PipelineRun ${CYAN}${BAD_RUN}${RESET}: ${BOLD}$(run_status "${BAD_RUN}")${RESET}"
echo -e "    build-image     : $(task_status "${BAD_RUN}" build-image)"
echo -e "    acs-image-check : ${RED}$(task_status "${BAD_RUN}" acs-image-check)${RESET}"
DEPLOY_ST="$(task_status "${BAD_RUN}" deploy-dev)"
echo -e "    deploy-dev      : ${YELLOW}${DEPLOY_ST:-not run}${RESET}"
echo ""
pause

step "Why it failed — the ACS findings for this image"
show_cmd "tkn pipelinerun logs ${BAD_RUN} -n ${CICD_PROJECT} -t acs-image-check"
ACS_LOG="$(tkn pipelinerun logs "${BAD_RUN}" -n "${CICD_PROJECT}" -t acs-image-check 2>/dev/null || true)"
echo -e "  ${BOLD}CRITICAL vulnerabilities (image-scan):${RESET}"
awk -F'|' '/\[acs-image-check : image-scan\] \|/ && $5 ~ /CRITICAL/ {
    for (i = 2; i <= 9; i++) gsub(/^ +| +$/, "", $i)
    printf "    %-40s %-10s %-16s %-9s fixed in %s\n", $2, $3, $4, $5, $8 }' <<< "${ACS_LOG}"
echo ""
echo -e "  ${BOLD}Violated policies (image-check):${RESET}"
awk -F'|' '/\[acs-image-check : image-check\] \|/ && $2 !~ /^ *(POLICY)? *$/ {
    for (i = 2; i <= 4; i++) gsub(/^ +| +$/, "", $i)
    printf "    %-55s %-9s breaks build: %s\n", $2, $3, ($4 == "X" ? "YES" : "no") }' <<< "${ACS_LOG}"
echo ""
grep -E 'ERROR:.*failed policies' <<< "${ACS_LOG}" | head -1 | sed 's/^\[[^]]*\] /  /' | cut -c1-160
echo ""
echo -e "  ${BOLD}Running in ${DEV_PROJECT}:${RESET} ${CYAN}$(dev_image)${RESET}"
[[ "$(dev_image)" == "${GOOD_IMAGE}" ]] && ok "Unchanged — the vulnerable image was pushed to the registry but never deployed"
echo ""
cat <<'MSG'
  The image exists in the registry (build + push succeeded) — but ACS stopped
  the pipeline before deploy-dev. Production-grade: also enforce the same
  policy at DEPLOY time (admission controller), so nobody can `oc set image` it.
MSG
echo ""
pause

# ─────────────────────────────────────────────────────────────────────────────
# PART 4 — Fix: revert, run again
# ─────────────────────────────────────────────────────────────────────────────
header "PART 4 — Fix it: revert the commit"

REVERT_SHA=""
step "Revert the vulnerable commit in GitLab"
show_cmd "POST ${GL_API}/projects/${PROJECT_ENC}/repository/commits/${BAD_SHA:-<sha>}/revert
  { branch: main }"
if grep -q "<artifactId>${VULN_DEP_ARTIFACT}</artifactId>" <<< "$(pom_on_main)"; then
  [[ -n "${BAD_SHA}" ]] || { warn "Could not find the commit '${VULN_COMMIT_MSG}' to revert"; exit 1; }
  RESP="$(gl_api POST "/projects/${PROJECT_ENC}/repository/commits/${BAD_SHA}/revert" --data '{"branch":"main"}')"
  REVERT_SHA="$(jq -r '.id // empty' <<< "${RESP}")"
  [[ -n "${REVERT_SHA}" ]] || { warn "Revert failed: ${RESP}"; exit 1; }
  ok "Reverted: ${GITLAB_URL}/${PROJECT_PATH}/-/commit/${REVERT_SHA}"
else
  ok "pom.xml on main has no ${VULN_DEP_ARTIFACT} — nothing to revert"
fi
echo ""
pause

if [[ -n "${REVERT_SHA}" ]] && pac_enabled; then
  step "The revert is a push to main → Pipelines-as-Code runs the pipeline"
  wait_pac_run "${REVERT_SHA}"
  GOOD_RUN="${PAC_RUN}"
else
  step "Run the pipeline again"
  show_cmd "tkn pipeline start ${PIPELINE_NAME} -n ${CICD_PROJECT} ... --showlog"
  start_build_run
  GOOD_RUN="$(last_build_run)"
fi
echo ""
STATUS="$(run_status "${GOOD_RUN}")"
if run_succeeded "${GOOD_RUN}"; then
  ok "PipelineRun '${GOOD_RUN}': ${STATUS} — gate open, deployed"
else
  warn "PipelineRun '${GOOD_RUN}': ${STATUS}"
fi
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# PART 5 — Recap
# ─────────────────────────────────────────────────────────────────────────────
header "PART 5 — Recap"

show_cmd "tkn pipelinerun list -n ${CICD_PROJECT} --limit 3"
tkn pipelinerun list -n "${CICD_PROJECT}" --limit 3
echo ""
echo -e "  ${BOLD}Running in ${DEV_PROJECT}:${RESET} ${CYAN}$(dev_image)${RESET}"
echo -e "  ${BOLD}from commit            :${RESET} ${CYAN}$(dev_commit)${RESET}"
APP_HOST="$(oc get route "${APP_NAME}" -n "${DEV_PROJECT}" -o jsonpath='{.spec.host}' 2>/dev/null || true)"
[[ -n "${APP_HOST}" ]] && echo -e "  ${BOLD}/api/info              :${RESET} ${GREEN}$(curl -sk "https://${APP_HOST}/api/info" || echo 'no response')${RESET}"
echo ""
cat <<'MSG'
  • The policy lives in ACS, not in the pipeline YAML — security owns the rule,
    every pipeline that calls `roxctl image check` obeys it
  • Failing fast in CI is cheap; the same CVE found in production is not
  • The fix went through Git (revert) — the pipeline did the rest
MSG
echo ""
ok "DevSecOps gate demonstrated: vulnerable build blocked, fixed build deployed."
echo ""

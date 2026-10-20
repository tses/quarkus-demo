#!/usr/bin/env bash
# =============================================================================
# 32-pipeline-build-deploy.sh — ACT 5: CI pipeline build → scan → deploy
#
# Pipeline 'build-deploy' (project CICD_PROJECT):
#   git-clone (GitLab) → maven-cached (persistent Maven repo PVC) →
#   buildah (push to GitLab registry) → acs-image-check (roxctl scan + check,
#   delegated to this secured cluster) → inline oc task (deploy to DEV_PROJECT)
#
# Prerequisites: scripts/30-gitlab-setup.sh (GitLab, coschedule, registry CA),
# ACS API token in KEYS_FILE as "acs:<token>".
# Idempotent: Secrets/PVC/Tasks/Pipeline via `oc apply`, ACS integration is
# upserted; every run starts a new PipelineRun.
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/demo-config.sh"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="cicd/tekton/build"
WS_TEMPLATE="cicd/tekton/intro/workspace-template.yaml"
cd "${REPO_ROOT}"

header "ACT 5 — Build & Deploy Pipeline (Tekton + ACS)"

check_login
for bin in tkn jq curl; do
  command -v "${bin}" &>/dev/null || { warn "'${bin}' not found in PATH"; exit 1; }
done

GITLAB_URL="https://$(get_gitlab_host)"
GIT_URL="${GITLAB_URL}/${GITLAB_GROUP}/${GITLAB_PROJECT}.git"
REG_HOST="$(get_gitlab_registry_host)"
IMAGE_REPO="$(get_app_image_repo)"
CI_USER="$(get_gitlab_cred ci-username)"
CI_TOKEN="$(get_gitlab_cred ci-token)"
[[ -n "${CI_USER}" && -n "${CI_TOKEN}" ]] || { warn "GitLab CI token not found — run scripts/30-gitlab-setup.sh first"; exit 1; }
ACS_TOKEN="$(get_key "${ACS_TOKEN_KEY}")"
[[ -n "${ACS_TOKEN}" ]] || { warn "ACS API token not found: add '${ACS_TOKEN_KEY}:<token>' to ${KEYS_FILE}"; exit 1; }
[[ -n "${ACS_CENTRAL_URL}" ]] || { warn "ACS Central URL not found: add '${ACS_URL_KEY}:https://<central>' to ${KEYS_FILE}"; exit 1; }
ACS_CLUSTER_NAME="$(get_acs_cluster)"
[[ -n "${ACS_CLUSTER_NAME}" ]] || { warn "No SecuredCluster found — set ACS_CLUSTER in demo-config.sh"; exit 1; }
ACS_ENDPOINT="${ACS_CENTRAL_URL#https://}"; ACS_ENDPOINT="${ACS_ENDPOINT%%/*}:443"
CONSOLE_URL="$(get_console_url)"

rox_api() {
  local method="$1" path="$2"; shift 2
  curl -sk -X "${method}" -H "Authorization: Bearer ${ACS_TOKEN}" \
    -H 'Content-Type: application/json' "${ACS_CENTRAL_URL}${path}" "$@"
}

echo -e "  ${BOLD}Pipelines :${RESET} ${CYAN}${CICD_PROJECT}${RESET}   ${BOLD}App :${RESET} ${CYAN}${DEV_PROJECT}${RESET}"
echo -e "  ${BOLD}Source    :${RESET} ${CYAN}${GIT_URL}${RESET}"
echo -e "  ${BOLD}Image     :${RESET} ${CYAN}${IMAGE_REPO}${RESET}"
echo -e "  ${BOLD}ACS       :${RESET} ${CYAN}${ACS_CENTRAL_URL}${RESET} (cluster ${ACS_CLUSTER_NAME})"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# PART 1 — What we are building
# ─────────────────────────────────────────────────────────────────────────────
header "PART 1 — A real CI pipeline"

cat <<'MSG'
   GitLab repo ──► fetch-source ──► build-jar ──► build-image ──► acs-image-check ──► deploy-dev
                   (git-clone)      (Maven,       (buildah →      (roxctl scan +       (oc, image
                                     cached)       GitLab          policy check)        by digest)
                                                   registry)

  • Every box is a Task = a Pod; the source travels in a shared workspace (PVC)
  • The image is deployed by DIGEST → exactly what ACS scanned is what runs
  • ACS Central is in the cloud; the scan is DELEGATED to this cluster's scanner,
    because the cloud cannot reach our in-cluster registry
MSG
echo ""
pause

# ─────────────────────────────────────────────────────────────────────────────
# PART 2 — Prepare: projects, credentials, ACS, Maven cache
# ─────────────────────────────────────────────────────────────────────────────
header "PART 2 — Prepare projects, credentials and cache"

step "Projects: pipelines run in '${CICD_PROJECT}', the app is deployed to '${DEV_PROJECT}'"
show_cmd "oc new-project ${DEV_PROJECT}
oc policy add-role-to-user edit system:serviceaccount:${CICD_PROJECT}:pipeline -n ${DEV_PROJECT}" \
  "Create project + grant the pipeline SA the edit role" \
  "Console → Home → Projects → Create Project
Console → User Management → RoleBindings → Create binding (ServiceAccount ${CICD_PROJECT}/pipeline, ClusterRole edit)"
for ns in "${CICD_PROJECT}:${CICD_PROJECT_DISPLAY}" "${DEV_PROJECT}:${DEV_PROJECT_DISPLAY}"; do
  oc get project "${ns%%:*}" &>/dev/null || \
    oc new-project "${ns%%:*}" --display-name="${ns#*:}" --skip-config-write >/dev/null
done
for _ in $(seq 1 30); do oc get sa pipeline -n "${CICD_PROJECT}" &>/dev/null && break; sleep 2; done
if argo_enabled; then
  ok "Argo CD manages '${DEV_PROJECT}' (step 36+) — the pipeline delivers through Git, no edit role granted"
else
  oc policy add-role-to-user edit "system:serviceaccount:${CICD_PROJECT}:pipeline" -n "${DEV_PROJECT}" >/dev/null
  ok "SA '${CICD_PROJECT}/pipeline' may deploy into '${DEV_PROJECT}' (edit role, nothing more)"
fi
echo ""
pause

step "Registry credentials: push from the pipeline, pull in the dev project (GitLab token '${GITLAB_CI_TOKEN_NAME}')"
show_cmd "oc create secret docker-registry ${REGISTRY_SECRET} --docker-server=${REG_HOST} \\
  --docker-username=${CI_USER} --docker-password=<ci-token> -n ${CICD_PROJECT}   # + same in ${DEV_PROJECT}
oc secrets link default ${REGISTRY_SECRET} --for=pull -n ${DEV_PROJECT}" \
  "Create registry Secret + link it for image pulls" \
  "Console → Workloads → Secrets → Create → Image pull secret (in both projects)
Console → User Management → ServiceAccounts → default → YAML: add to imagePullSecrets"
for ns in "${CICD_PROJECT}" "${DEV_PROJECT}"; do
  oc create secret docker-registry "${REGISTRY_SECRET}" -n "${ns}" --docker-server="${REG_HOST}" \
    --docker-username="${CI_USER}" --docker-password="${CI_TOKEN}" --dry-run=client -o yaml | oc apply -f - >/dev/null
done
oc secrets link default "${REGISTRY_SECRET}" --for=pull -n "${DEV_PROJECT}"
ok "Secret '${REGISTRY_SECRET}' in ${CICD_PROJECT} (buildah push) and ${DEV_PROJECT} (kubelet pull)"
echo ""
pause

step "ACS: API token for roxctl (Secret '${ACS_SECRET}') — the token stays out of Git"
show_cmd "oc create secret generic ${ACS_SECRET} -n ${CICD_PROJECT} \\
  --from-literal=endpoint=${ACS_ENDPOINT} \\
  --from-literal=token=<acs-api-token> \\
  --from-literal=cluster=${ACS_CLUSTER_NAME}" \
  "Create Secret with the ACS API token" \
  "ACS → Platform Configuration → Integrations → API Token → Generate token
Console → Workloads → Secrets → Create → Key/value secret"
oc create secret generic "${ACS_SECRET}" -n "${CICD_PROJECT}" \
  --from-literal=endpoint="${ACS_ENDPOINT}" --from-literal=token="${ACS_TOKEN}" \
  --from-literal=cluster="${ACS_CLUSTER_NAME}" --dry-run=client -o yaml | oc apply -f - >/dev/null
ok "Secret '${ACS_SECRET}' ready"
echo ""

step "ACS: registry integration (pull credentials) + delegated scanning for '${REG_HOST}'"
show_cmd "POST/PUT ${ACS_CENTRAL_URL}/v1/imageintegrations
  { name: ${ACS_REGISTRY_INTEGRATION}, type: docker, endpoint: ${REG_HOST},
    username: ${CI_USER}, password: <ci-token>, insecure: true }
GET/PUT ${ACS_CENTRAL_URL}/v1/delegatedregistryconfig
  registries += { path: ${REG_HOST}, cluster: ${ACS_CLUSTER_NAME} }" \
  "Create ACS registry integration + enable delegated scanning" \
  "ACS → Platform Configuration → Integrations → Generic Docker Registry → New integration
ACS → Platform Configuration → Clusters → Delegated image scanning → add registry"
INTEG_ID="$(rox_api GET /v1/imageintegrations \
  | jq -r --arg n "${ACS_REGISTRY_INTEGRATION}" '.integrations[]? | select(.name == $n) | .id' | head -1)"
INTEG_BODY="$(jq -nc --arg n "${ACS_REGISTRY_INTEGRATION}" --arg ep "${REG_HOST}" \
  --arg u "${CI_USER}" --arg p "${CI_TOKEN}" --arg id "${INTEG_ID}" '{
    name: $n, type: "docker", categories: ["REGISTRY"],
    docker: {endpoint: $ep, username: $u, password: $p, insecure: true},
    skipTestIntegration: true} + (if $id != "" then {id: $id} else {} end)')"
if [[ -n "${INTEG_ID}" ]]; then
  rox_api PUT "/v1/imageintegrations/${INTEG_ID}?updatePassword=true" --data "${INTEG_BODY}" >/dev/null
  ok "Image integration '${ACS_REGISTRY_INTEGRATION}' updated"
else
  INTEG_ID="$(rox_api POST /v1/imageintegrations --data "${INTEG_BODY}" | jq -r '.id // empty')"
  [[ -n "${INTEG_ID}" ]] || { warn "Could not create ACS image integration '${ACS_REGISTRY_INTEGRATION}'"; exit 1; }
  ok "Image integration '${ACS_REGISTRY_INTEGRATION}' created"
fi
CLUSTER_ID="$(rox_api GET /v1/clusters | jq -r --arg n "${ACS_CLUSTER_NAME}" '.clusters[]? | select(.name == $n) | .id')"
[[ -n "${CLUSTER_ID}" ]] || { warn "Cluster '${ACS_CLUSTER_NAME}' not known to ACS Central"; exit 1; }
DELEG="$(rox_api GET /v1/delegatedregistryconfig)"
if jq -e --arg r "${REG_HOST}" '.enabledFor != "NONE" and any(.registries[]?; .path == $r)' <<< "${DELEG}" >/dev/null; then
  ok "Delegated scanning already enabled for '${REG_HOST}'"
else
  NEW_DELEG="$(jq -c --arg r "${REG_HOST}" --arg c "${CLUSTER_ID}" '
    .enabledFor = (if .enabledFor == "ALL" then "ALL" else "SPECIFIC" end)
    | .defaultClusterId = (if (.defaultClusterId // "") == "" then $c else .defaultClusterId end)
    | .registries = ([.registries[]? | select(.path != $r)] + [{path: $r, clusterId: $c}])' <<< "${DELEG}")"
  rox_api PUT /v1/delegatedregistryconfig --data "${NEW_DELEG}" >/dev/null
  ok "Delegated scanning enabled for '${REG_HOST}' → cluster '${ACS_CLUSTER_NAME}'"
fi
echo ""
pause

step "ACS Scanner V4 pre-flight: the indexer builds its DB schema only at startup"
echo -e "  A node reboot can re-provision the scanner-v4-db PVC and leave the indexer"
echo -e "  talking to an empty database — every scan then fails with 'Database operation"
echo -e "  failed'. Restarting the indexer rebuilds the schema (no-op when it is intact)."
ensure_acs_scanner_ready
echo ""
pause

step "Maven cache: a persistent PVC, mounted as a second workspace by every run"
show_cmd "oc apply -n ${CICD_PROJECT} -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${MAVEN_CACHE_PVC}
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: ${MAVEN_CACHE_SIZE}
EOF" \
  "Create PVC for the Maven cache" \
  "Console → Storage → PersistentVolumeClaims → Create PersistentVolumeClaim"
cat <<EOF | oc apply -n "${CICD_PROJECT}" -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${MAVEN_CACHE_PVC}
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: ${MAVEN_CACHE_SIZE}
EOF
echo -e "  RWO is enough: affinity assistant (coschedule=pipelineruns) keeps a run's PVCs on one node."
echo ""
pause

# ─────────────────────────────────────────────────────────────────────────────
# PART 3 — Tasks and Pipeline
# ─────────────────────────────────────────────────────────────────────────────
header "PART 3 — Our Tasks and the Pipeline"

step "Task 'maven-cached': Maven with -Dmaven.repo.local on the cache workspace"
show_cmd "# ${BUILD_DIR}/task-maven-cached.yaml
$(cat "${BUILD_DIR}/task-maven-cached.yaml")" \
  "Create Task 'maven-cached'" \
  "Console → Pipelines → Tasks → Create → Task (paste the YAML)"
oc apply -n "${CICD_PROJECT}" -f "${BUILD_DIR}/task-maven-cached.yaml"
echo ""
pause

step "Task 'acs-image-check': roxctl image scan (report) + image check (gate)"
show_cmd "# ${BUILD_DIR}/task-acs-image-check.yaml
$(cat "${BUILD_DIR}/task-acs-image-check.yaml")" \
  "Create Task 'acs-image-check'" \
  "Console → Pipelines → Tasks → Create → Task (paste the YAML)"
oc apply -n "${CICD_PROJECT}" -f "${BUILD_DIR}/task-acs-image-check.yaml"
# GitOps delivery task (explained in step 37) — referenced by the pipeline, skipped while deploy-mode=oc
oc apply -n "${CICD_PROJECT}" -f "${BUILD_DIR}/task-gitops-update-image.yaml" >/dev/null
echo ""
pause

step "Pipeline 'build-deploy': 2 shipped Tasks (cluster resolver) + 2 of ours + 1 inline"
show_cmd "# ${BUILD_DIR}/pipeline-build-deploy.yaml
$(cat "${BUILD_DIR}/pipeline-build-deploy.yaml")" \
  "Create Pipeline '${PIPELINE_NAME}'" \
  "Console → Pipelines → Create → Pipeline (Pipeline builder or YAML view)"
oc apply -n "${CICD_PROJECT}" -f "${BUILD_DIR}/pipeline-build-deploy.yaml"
echo ""
echo -e "  ${BOLD}Graph in the console:${RESET} ${CYAN}${CONSOLE_URL}/k8s/ns/${CICD_PROJECT}/tekton.dev~v1~Pipeline/${PIPELINE_NAME}${RESET}"
echo ""
pause

# ─────────────────────────────────────────────────────────────────────────────
# PART 4 — Run it
# ─────────────────────────────────────────────────────────────────────────────
maven_time() {   # <pipelinerun> → "NNs" as reported by the maven-cached task
  tkn pipelinerun logs "$1" -n "${CICD_PROJECT}" -t build-jar 2>/dev/null \
    | grep -o 'Maven finished in [0-9]*s' | grep -o '[0-9]\+s' || echo "?"
}

header "PART 4 — Run the pipeline"

step "Start a PipelineRun (watch the graph in the console while the logs stream here)"
echo -e "  ${BOLD}PipelineRuns:${RESET} ${CYAN}${CONSOLE_URL}/k8s/ns/${CICD_PROJECT}/tekton.dev~v1~PipelineRun${RESET}"
echo ""
echo -e "  ${BOLD}-p = params${RESET}      → data (strings): \"what to do\". Declared in spec.params,
                     used as \$(params.x). --use-param-defaults fills in the rest
                     (git-revision=main, gitops-*). Visible in the PipelineRun YAML.
  ${BOLD}-w = workspaces${RESET}  → storage (volumes): \"where to do it\". Each task is its own
                     Pod, so files travel over a shared volume. The Pipeline names
                     the workspace, the run decides what is behind it:
    • source         volumeClaimTemplateFile → fresh PVC per run, deleted at the end
    • maven-repo     claimName → existing PVC, the Maven cache across runs
    • registry-auth  secret    → Secret mounted as a file (push credentials)"
echo ""
show_cmd "tkn pipeline start ${PIPELINE_NAME} -n ${CICD_PROJECT} \\
  -p git-url=${GIT_URL} \\
  -p image-repo=${IMAGE_REPO} \\
  -p dev-namespace=${DEV_PROJECT} -p app-name=${APP_NAME} \\
  -p deploy-mode=$(get_deploy_mode) \\
  -w name=source,volumeClaimTemplateFile=${WS_TEMPLATE} \\
  -w name=maven-repo,claimName=${MAVEN_CACHE_PVC} \\
  -w name=registry-auth,secret=${REGISTRY_SECRET} \\
  --use-param-defaults --showlog" \
  "Start a PipelineRun" \
  "Console → Pipelines → ${PIPELINE_NAME} → Actions → Start
  (params; workspaces: VolumeClaimTemplate / PersistentVolumeClaim / Secret)"
start_build_run
PR="$(last_build_run)"
echo ""
STATUS="$(oc get pipelinerun "${PR}" -n "${CICD_PROJECT}" -o jsonpath='{.status.conditions[0].reason}')"
if run_succeeded "${PR}"; then
  ok "PipelineRun '${PR}': ${STATUS}"
else
  warn "PipelineRun '${PR}': ${STATUS} — tkn pipelinerun describe ${PR} -n ${CICD_PROJECT}"
  exit 1
fi
echo ""
pause

# ─────────────────────────────────────────────────────────────────────────────
# PART 5 — Results
# ─────────────────────────────────────────────────────────────────────────────
header "PART 5 — What the pipeline produced"

step "Pipeline results and task durations"
show_cmd "tkn pipelinerun describe ${PR} -n ${CICD_PROJECT}" \
  "Inspect PipelineRun results" \
  "Console → Pipelines → PipelineRuns → ${PR} → Details (Results) / TaskRuns"
tkn pipelinerun describe "${PR}" -n "${CICD_PROJECT}" | sed -n '/Results/,$p' | grep -v '^$'
echo ""
pause

step "The app in '${DEV_PROJECT}' runs the image by digest, annotated with the Git commit"
show_cmd "oc get deployment ${APP_NAME} -n ${DEV_PROJECT} \\
  -o jsonpath='{.spec.template.spec.containers[0].image}'
oc get deployment ${APP_NAME} -n ${DEV_PROJECT} -o jsonpath='{.metadata.annotations}'
curl -sk https://\$(oc get route ${APP_NAME} -n ${DEV_PROJECT} -o jsonpath='{.spec.host}')/api/info" \
  "Inspect the deployed image + call the app" \
  "Console → Workloads → Deployments → ${APP_NAME} → YAML (image, annotations)
Console → Networking → Routes → ${APP_NAME} → Location"
echo -e "  Image      : ${CYAN}$(oc get deployment "${APP_NAME}" -n "${DEV_PROJECT}" -o jsonpath='{.spec.template.spec.containers[0].image}')${RESET}"
echo -e "  Git commit : ${CYAN}$(oc get deployment "${APP_NAME}" -n "${DEV_PROJECT}" -o jsonpath='{.metadata.annotations.ked-demo/git-commit}')${RESET}"
APP_HOST="$(oc get route "${APP_NAME}" -n "${DEV_PROJECT}" -o jsonpath='{.spec.host}')"
echo -e "  /api/info  : ${GREEN}$(curl -sk "https://${APP_HOST}/api/info" || echo 'no response')${RESET}"
echo ""
echo -e "  ${BOLD}App        :${RESET} ${CYAN}https://${APP_HOST}/api/info${RESET}"
echo -e "  ${BOLD}Registry   :${RESET} ${CYAN}${GITLAB_URL}/${GITLAB_GROUP}/${GITLAB_PROJECT}/container_registry${RESET}"
echo -e "  ${BOLD}ACS images :${RESET} ${CYAN}${ACS_CENTRAL_URL}/main/vulnerabilities/user-workloads/images${RESET}"
echo ""
pause

# ─────────────────────────────────────────────────────────────────────────────
# PART 6 — Maven cache pays off on the next run
# ─────────────────────────────────────────────────────────────────────────────
header "PART 6 — Second run: Maven cache"

FIRST_MVN="$(maven_time "${PR}")"
echo -e "  Maven took ${BOLD}${FIRST_MVN}${RESET} in run '${PR}' (Maven cache PVC: $(oc get pvc "${MAVEN_CACHE_PVC}" -n "${CICD_PROJECT}" -o jsonpath='{.status.capacity.storage}'))."
echo -n "  Start a second run to show the cached Maven repository? (y/N): "
read -r AGAIN
if [[ "${AGAIN}" =~ ^[Yy] ]]; then
  show_cmd "tkn pipeline start ${PIPELINE_NAME} ... (same parameters and workspaces)" \
    "Start a second PipelineRun" \
    "Console → Pipelines → PipelineRuns → ${PR} → Actions → Rerun"
  start_build_run
  PR2="$(last_build_run)"
  echo ""
  echo -e "  Maven: ${BOLD}${FIRST_MVN}${RESET} (${PR}) → ${BOLD}$(maven_time "${PR2}")${RESET} (${PR2})"
fi
echo ""

ok "CI pipeline: source → jar → image → ACS gate → deployed by digest."
echo -e "  Next: ${CYAN}./scripts/34-acs-image-check.sh${RESET} — the ACS gate stops a vulnerable build."
echo ""

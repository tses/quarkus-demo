#!/usr/bin/env bash
# =============================================================================
# 31-pipelines-intro.sh — ACT 5: OpenShift Pipelines (Tekton) introduction
#
# Live walkthrough of the Tekton building blocks on the real cluster:
#   operator & TektonConfig → ready-made Tasks (cluster resolver catalog) →
#   Step / Task / Params / Results (hello Task) →
#   Pipeline / Workspaces / Results between tasks (clone the app repo from
#   the in-cluster GitLab) → console Pipelines view.
#
# Prerequisite: scripts/30-gitlab-setup.sh (GitLab + app repo).
# Idempotent: Task/Pipeline are applied with `oc apply`; every run starts a
# new TaskRun/PipelineRun.
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/demo-config.sh"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INTRO_DIR="cicd/tekton/intro"
HELLO_TASK="${INTRO_DIR}/hello-task.yaml"
INTRO_PIPELINE="${INTRO_DIR}/inspect-source-pipeline.yaml"
WS_TEMPLATE="${INTRO_DIR}/workspace-template.yaml"
cd "${REPO_ROOT}"

header "ACT 5 — OpenShift Pipelines (Tekton): Introduction"

check_login
command -v tkn &>/dev/null || { warn "'tkn' CLI not found in PATH (Console → ? → Command Line Tools)"; exit 1; }

GITLAB_URL="https://$(get_gitlab_host)"
GIT_URL="${GITLAB_URL}/${GITLAB_GROUP}/${GITLAB_PROJECT}.git"
CONSOLE_URL="$(get_console_url)"

# ─────────────────────────────────────────────────────────────────────────────
# PART 1 — The platform: operator-managed Tekton
# ─────────────────────────────────────────────────────────────────────────────
header "PART 1 — OpenShift Pipelines is installed by an Operator"

cat <<'MSG'
  OpenShift CI/CD = two operators, two jobs:
    • OpenShift Pipelines (Tekton)  → CI : build, test, scan, push the image
    • OpenShift GitOps   (Argo CD)  → CD : sync the cluster with Git (later)

  Tekton is Kubernetes-native: pipelines are CRDs, every run is Pods.
  No CI server to install, patch or scale — the cluster IS the CI engine.
MSG
echo ""
pause

step "Operator + its single config object (TektonConfig)"
show_cmd "oc get csv -n openshift-operators | grep -i pipelines
oc get tektonconfig config"
oc get csv -n openshift-operators --no-headers 2>/dev/null | grep -i pipelines \
  | awk '{print "  " $1 "   " $NF}' || warn "OpenShift Pipelines operator not found"
echo ""
oc get tektonconfig config
echo ""
pause

step "What the operator deployed (one TektonConfig → several components)"
show_cmd "oc get tektonpipeline,tektontrigger,tektonchain,tektonresult,openshiftpipelinesascode
tkn version"
oc get tektonpipeline,tektontrigger,tektonchain,tektonresult,openshiftpipelinesascode 2>/dev/null
echo ""
tkn version
echo ""
cat <<'MSG'
  Pipelines         → the engine (Task, Pipeline, TaskRun, PipelineRun)
  Triggers          → start runs from events (webhooks)
  Chains            → sign & attest what the pipeline built (supply chain)
  Results           → long-term run history (database), survives pruning
  Pipelines-as-Code → pipelines live in the app's Git repo (.tekton/) — step 35
MSG
echo ""
pause

# ─────────────────────────────────────────────────────────────────────────────
# PART 2 — Ready-made Tasks
# ─────────────────────────────────────────────────────────────────────────────
header "PART 2 — Don't write everything: ready-made Tasks"

step "Tasks shipped with OpenShift Pipelines (namespace ${TEKTON_NAMESPACE})"
show_cmd "tkn task list -n ${TEKTON_NAMESPACE} -o name | sed 's|.*/||' \\
  | grep -Ev -- '-[0-9]+-[0-9]+-[0-9]+\$' | column -c 100"
tkn task list -n "${TEKTON_NAMESPACE}" -o name | sed 's|.*/||' \
  | grep -Ev -- '-[0-9]+-[0-9]+-[0-9]+$' | column -c 100
echo ""
echo -e "  ${BOLD}Versioned copies${RESET} (e.g. git-clone-1-24-0) are filtered out above — pin them for reproducible pipelines."
echo -e "  Pipelines reference these Tasks with the ${BOLD}cluster resolver${RESET} — no copy in our namespace."
echo ""
pause

step "Anatomy of a Task: git-clone — params in, results out, workspaces to share files"
show_cmd "tkn task describe git-clone -n ${TEKTON_NAMESPACE}"
tkn task describe git-clone -n "${TEKTON_NAMESPACE}" \
  | sed -n '/Params/,/Steps/p' | sed '$d' | grep -v '^$' | grep -v -- '---$'
echo ""
pause

# ─────────────────────────────────────────────────────────────────────────────
# PART 3 — Step / Task / Params / Results
# ─────────────────────────────────────────────────────────────────────────────
header "PART 3 — Step → Task: our first Task"

step "Project for the CI pipelines: ${CICD_PROJECT}"
show_cmd "oc new-project ${CICD_PROJECT} --display-name='${CICD_PROJECT_DISPLAY}'"
if oc get project "${CICD_PROJECT}" &>/dev/null; then
  ok "Project '${CICD_PROJECT}' already exists"
else
  oc new-project "${CICD_PROJECT}" --display-name="${CICD_PROJECT_DISPLAY}" --skip-config-write >/dev/null
  ok "Project '${CICD_PROJECT}' created"
fi
for _ in $(seq 1 30); do
  oc get sa pipeline -n "${CICD_PROJECT}" &>/dev/null && break
  sleep 2
done
ok "ServiceAccount 'pipeline' created by the operator in every namespace — runs use it by default"
echo ""
pause

step "Task 'hello': 1 param, 1 result, 2 steps"
show_cmd "# ${HELLO_TASK}
$(cat "${HELLO_TASK}")

→ oc apply -n ${CICD_PROJECT} -f ${HELLO_TASK}"
oc apply -n "${CICD_PROJECT}" -f "${HELLO_TASK}"
echo ""
pause

step "Run it: a TaskRun → one Pod, one container per step"
show_cmd "tkn task start hello -n ${CICD_PROJECT} -p name=KED --showlog"
tkn task start hello -n "${CICD_PROJECT}" -p name=KED --showlog
echo ""

TR="$(oc get taskrun -n "${CICD_PROJECT}" -l tekton.dev/task=hello \
  --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].metadata.name}')"
step "Behind the scenes: TaskRun '${TR}'"
show_cmd "oc get pod -n ${CICD_PROJECT} -l tekton.dev/taskRun=${TR} \\
  -o jsonpath='{.items[0].spec.containers[*].name}'
tkn taskrun describe ${TR} -n ${CICD_PROJECT}"
echo -e "  Containers of the Pod : ${CYAN}$(oc get pod -n "${CICD_PROJECT}" -l "tekton.dev/taskRun=${TR}" \
  -o jsonpath='{.items[0].spec.containers[*].name}')${RESET}"
echo ""
tkn taskrun describe "${TR}" -n "${CICD_PROJECT}" | sed -n '/Params/,$p' | grep -v '^$'
echo ""
cat <<'MSG'
  Step  = a container (image + script)
  Task  = ordered steps in ONE Pod (they share the Pod's volumes)
  Param = input · Result = small output (a string) other tasks can consume
MSG
echo ""
pause

# ─────────────────────────────────────────────────────────────────────────────
# PART 4 — Pipeline / Workspaces / Results between Tasks
# ─────────────────────────────────────────────────────────────────────────────
header "PART 4 — Task → Pipeline: clone the app from GitLab"

step "Pipeline 'inspect-source': git-clone (cluster resolver) → inline Task"
show_cmd "# ${INTRO_PIPELINE}
$(cat "${INTRO_PIPELINE}")

→ oc apply -n ${CICD_PROJECT} -f ${INTRO_PIPELINE}"
oc apply -n "${CICD_PROJECT}" -f "${INTRO_PIPELINE}"
echo ""
cat <<'MSG'
  • Workspace 'source' = a volume shared by the tasks (each task is its own Pod)
  • $(tasks.fetch-source.results.COMMIT) = data flow AND ordering:
    inspect-source waits for fetch-source — no explicit runAfter needed
MSG
echo ""
pause

step "Start it — the workspace gets a fresh PVC per run (volumeClaimTemplate)"
show_cmd "# ${WS_TEMPLATE}
$(cat "${WS_TEMPLATE}")

→ tkn pipeline start inspect-source -n ${CICD_PROJECT} \\
    -p git-url=${GIT_URL} \\
    -w name=source,volumeClaimTemplateFile=${WS_TEMPLATE} \\
    --use-param-defaults --showlog"
tkn pipeline start inspect-source -n "${CICD_PROJECT}" \
  -p git-url="${GIT_URL}" \
  -w name=source,volumeClaimTemplateFile="${WS_TEMPLATE}" \
  --use-param-defaults --showlog
echo ""

PR="$(oc get pipelinerun -n "${CICD_PROJECT}" -l tekton.dev/pipeline=inspect-source \
  --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].metadata.name}')"
STATUS="$(oc get pipelinerun "${PR}" -n "${CICD_PROJECT}" -o jsonpath='{.status.conditions[0].reason}')"
[[ "${STATUS}" == "Succeeded" ]] && ok "PipelineRun '${PR}': ${STATUS}" || warn "PipelineRun '${PR}': ${STATUS}"
echo ""
pause

step "One PipelineRun → one TaskRun (and Pod) per task"
show_cmd "tkn pipelinerun describe ${PR} -n ${CICD_PROJECT}
oc get taskrun,pod -n ${CICD_PROJECT} -l tekton.dev/pipelineRun=${PR}"
tkn pipelinerun describe "${PR}" -n "${CICD_PROJECT}" | sed -n '/Workspaces/,$p' | grep -v '^$'
echo ""
oc get taskrun,pod -n "${CICD_PROJECT}" -l "tekton.dev/pipelineRun=${PR}"
echo ""
pause

# ─────────────────────────────────────────────────────────────────────────────
# PART 5 — Console
# ─────────────────────────────────────────────────────────────────────────────
header "PART 5 — Same objects in the OpenShift console"

echo -e "  ${BOLD}Pipelines   :${RESET} ${CYAN}${CONSOLE_URL}/dev-pipelines/ns/${CICD_PROJECT}${RESET}"
echo -e "  ${BOLD}Last run    :${RESET} ${CYAN}${CONSOLE_URL}/k8s/ns/${CICD_PROJECT}/tekton.dev~v1~PipelineRun/${PR}${RESET}"
echo -e "  ${BOLD}Tasks       :${RESET} ${CYAN}${CONSOLE_URL}/k8s/ns/${CICD_PROJECT}/tekton.dev~v1~Task${RESET}"
echo -e "  ${BOLD}App repo    :${RESET} ${CYAN}${GITLAB_URL}/${GITLAB_GROUP}/${GITLAB_PROJECT}${RESET}"
echo ""
cat <<'MSG'
  Show in the console:
    • Pipelines → inspect-source → graph (task boxes, the arrow comes from the Result)
    • PipelineRun → Logs per task, Results, TaskRuns, Parameters
    • Pipeline Builder (Actions → Edit Pipeline): add a ready-made Task from the catalog
MSG
echo ""

ok "Tekton building blocks covered: Step · Task · Params · Results · Pipeline · Workspaces · Runs."
echo -e "  Next: ${CYAN}./scripts/32-pipeline-build-deploy.sh${RESET} — build, scan and deploy the app."
echo ""

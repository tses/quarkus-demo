#!/usr/bin/env bash
# =============================================================================
# demo-config.sh — Central configuration for all demo scripts
# Source this file at the top of every script: source "$(dirname "$0")/demo-config.sh"
# =============================================================================

# -----------------------------------------------------------------------------
# CLUSTER SETTINGS — auto-detected from active oc login session
# Run: oc login <cluster-url> before starting the demo. No need to edit these.
# -----------------------------------------------------------------------------
# OCP_CONSOLE_URL is derived lazily at runtime — do NOT evaluate at source time
# to avoid DNS issues. Use: oc whoami --show-console  (OCP 4.x)
get_console_url() {
  oc whoami --show-console 2>/dev/null || \
    echo "https://console-openshift-console.apps.$(oc whoami --show-server 2>/dev/null | sed 's|https://api\.||;s|:6443||')"
}

# -----------------------------------------------------------------------------
# PROJECT / NAMESPACE — change this if you want a different namespace name
# -----------------------------------------------------------------------------
export DEMO_PROJECT_CONSOLE="ocp-demo-app-console"
export DEMO_PROJECT_CONSOLE_DISPLAY="OCP Demo App Console"
export DEMO_PROJECT="ocp-demo"
export DEMO_PROJECT_DISPLAY="OCP Introduction Demo"

# -----------------------------------------------------------------------------
# APPLICATION — quarkus-quickstarts/getting-started
# -----------------------------------------------------------------------------
export APP_NAME="ocp-demo-app"
export APP_NAME_V2="ocp-demo-app-v2"
export GIT_REPO="https://github.com/tses/quarkus-demo"   # ← update to your fork
export GIT_CONTEXT_DIR="app/ocp-demo-app"
export GIT_REF_V1="main"
export GIT_REF_V2="main"                      # same repo, patch APP_COLOUR=green for v2
export BUILDER_IMAGE="java:openjdk-17-ubi8"   # java imagestream in openshift namespace

# -----------------------------------------------------------------------------
# DATABASE (Postgres Operator) — lives in its OWN namespace (separate from app)
# -----------------------------------------------------------------------------
export DB_CLUSTER_NAME="demo-db"
export DB_NAMESPACE="ocp-demo-db"
export DB_NAMESPACE_DISPLAY="OCP Demo Database"

# -----------------------------------------------------------------------------
# ACT 4 — CONNECTIVITY LINK / GATEWAY API (Kuadrant)
# The Gateway is reconciled by the gateway controller available on the cluster.
# On OpenShift the built-in GatewayClass is "openshift-default". With OpenShift
# Connectivity Link (Kuadrant) the Istio controller exposes the "istio" class.
# Adjust GATEWAY_CLASS to match `oc get gatewayclass` on your cluster.
# -----------------------------------------------------------------------------
export GATEWAY_NAME="demo-gateway"
export GATEWAY_CLASS="openshift-default"
export GATEWAY_NAMESPACE="${DEMO_PROJECT}"
# Gateway API listeners use a DEDICATED subdomain, separate from the default
# Router/Route wildcard (*.apps.<cluster>). Leave empty to auto-derive it from
# the apps domain by swapping the leading "apps." prefix for "api.".
export GATEWAY_DOMAIN=""

# ── TLSPolicy (step 14) — cert-manager issuer used to secure the Gateway ─────
# The Gateway gains an HTTPS listener whose certificate is provisioned by
# cert-manager via the issuer referenced below. The demo cluster ships a
# Ready "self-signed" ClusterIssuer; swap to a real (e.g. ACME/Let's Encrypt)
# issuer for production-like certs.
export GATEWAY_TLS_POLICY_NAME="demo-gateway-tls"
export GATEWAY_TLS_SECRET="demo-gateway-tls"
export GATEWAY_TLS_ISSUER="self-signed"
export GATEWAY_TLS_ISSUER_KIND="ClusterIssuer"

# ── AuthPolicy (step 15) — protect the exposed API with API key auth ─────────
# Kuadrant's Authorino enforces authentication at the Gateway. The demo uses
# API key authentication: callers must send `Authorization: APIKEY <key>`.
# API keys are stored as labelled Secrets that Authorino reconciles.
export AUTH_POLICY_NAME="demo-app-auth"
export AUTH_API_KEY_SECRET="demo-app-apikey"
export AUTH_API_KEY_LABEL="${APP_NAME}"          # value of the app label selector
export AUTH_API_KEY_VALUE="demo-secret-key-123"  # the demo API key (not for prod!)
export AUTH_HEADER_PREFIX="APIKEY"

# ── RateLimitPolicy (step 16) — throttle request volume on the API ───────────
# Kuadrant's Limitador enforces request quotas at the Gateway. The demo uses a
# deliberately low limit so the throttle is easy to trigger live: after
# RATE_LIMIT requests within RATE_WINDOW, further calls get HTTP 429.
export RATE_LIMIT_POLICY_NAME="demo-app-ratelimit"
export RATE_LIMIT="5"          # max requests allowed per window
export RATE_WINDOW="10s"       # rolling window (Limitador duration syntax)
export RATE_LIMIT_BURST="8"    # how many calls the demo fires to cross the limit

# ── External metadata authorization (step 17) — separate route + FQDN ────────
# A SECOND HTTPRoute on its own hostname (same Gateway, same backend Service)
# demonstrates dynamic, runtime authorization. This route does NOT authenticate
# (anonymous) — it trusts a client identity header forwarded by an upstream WAF
# (mTLS at the edge). Authorino fetches the caller's tier LIVE from an external
# metadata service and a RateLimitPolicy applies a per-tier, per-client quota.
export MTLS_ROUTE_NAME="${APP_NAME}-mtls"          # new HTTPRoute (FQDN: <name>.api.<domain>)
export MTLS_AUTH_POLICY_NAME="demo-app-mtls-auth"  # anonymous + external metadata
export MTLS_RL_POLICY_NAME="demo-app-mtls-rl"      # per-tier rate limit
export META_SVC_NAME="metadata-svc"                # external metadata service
export META_SVC_PORT="8080"
export MTLS_CLIENT_HEADER="X-Client-Id"            # identity header set by the WAF
# Demo clients → tier mapping (kept in sync with the metadata-svc tier map).
export MTLS_GOLD_CLIENT="user1"
export MTLS_GOLD_LIMIT="5"
export MTLS_SILVER_CLIENT="user2"
export MTLS_SILVER_LIMIT="2"
export MTLS_TIER_WINDOW="10s"
export MTLS_UNKNOWN_CLIENT="ghost"   # not in the tier map → rejected (403)
export MTLS_BURST="7"                # calls fired per client to cross the limit

# ── Observability (step 18) — generate traffic so Grafana dashboards light up ─
# CL plugs into the cluster's user-workload monitoring. Dashboards (and
# istio_requests_total) only populate once requests flow through the Gateway.
# This step fires a steady stream of requests across the step-13/16 route and
# the step-17 per-tier route so request-rate / error-rate / 429 panels fill in.
export OBS_KUADRANT_NAME="kuadrant"        # Kuadrant CR carrying spec.observability
export OBS_KUADRANT_NS="kuadrant-system"   # namespace of the Kuadrant CR
export OBS_GRAFANA_NS="monitoring"         # namespace hosting Grafana
export OBS_TRAFFIC_ROUNDS="30"             # number of request batches to send
export OBS_TRAFFIC_DELAY="2"               # seconds between batches

# -----------------------------------------------------------------------------
# ACT 5 — CI/CD (OpenShift Pipelines + GitOps)
# Isolated namespaces so ACT 5 never touches the ACT 1–4 resources.
# -----------------------------------------------------------------------------
export CICD_PROJECT="ocp-demo-cicd"          # Tekton pipelines run here
export CICD_PROJECT_DISPLAY="OCP Demo CI/CD"
export DEV_PROJECT="ocp-demo-dev"            # app deployed by the pipeline
export DEV_PROJECT_DISPLAY="OCP Demo Dev"

# ── GitLab Omnibus (step 30, pre-demo) — in-cluster Git + Container Registry ─
# gitlab-ce container (bundled Redis + Registry) backed by a SEPARATE
# PostgreSQL 17 deployed first (Rails DB + registry metadata DB).
# Hostnames default to gitlab.<apps-domain> / registry.<apps-domain>; set them
# explicitly to override. Credentials are generated at setup time and kept in
# the cluster Secret GITLAB_CREDS_SECRET (never in this repo).
export GITLAB_NAMESPACE="gitlab"
export GITLAB_IMAGE="docker.io/gitlab/gitlab-ce:19.4.2-ce.0"
export GITLAB_POSTGRES_IMAGE="registry.access.redhat.com/hi/postgresql:17.10"  # GitLab 19 needs PG 17
export GITLAB_HOST=""                        # empty → gitlab.<apps-domain>
export GITLAB_REGISTRY_HOST=""               # empty → registry.<apps-domain>
export GITLAB_CREDS_SECRET="gitlab-demo-credentials"
export GITLAB_GROUP="ked-demo"
export GITLAB_PROJECT="${APP_NAME}"          # app repo = app/ocp-demo-app only
export GITLAB_SEED_DIR="${GIT_CONTEXT_DIR}"  # repo-relative dir pushed as the app repo
export GITLAB_CI_TOKEN_NAME="tekton-ci"      # project access token used by Tekton
export STORAGE_CLASS=""                      # empty → cluster default SC, else the first SC found

# ── OpenShift Pipelines (step 30 prep, steps 31+) ────────────────────────────
# The pipeline binds TWO PVC workspaces to the maven task (per-run source +
# persistent Maven cache). The default affinity-assistant mode "workspaces"
# rejects that ("more than one PersistentVolumeClaim is bound"), so step 30
# switches TektonConfig to "pipelineruns" (all PVCs of a run on one node — no
# RWX needed). The previous value is kept in an annotation for 39-teardown.
export TEKTON_NAMESPACE="openshift-pipelines"   # operator / cluster-resolver tasks
export TEKTON_COSCHEDULE="pipelineruns"
export TEKTON_COSCHEDULE_ANNOTATION="ked-demo/original-coschedule"

# Nodes must trust the GitLab registry certificate (self-signed Router CA) to
# pull the images the pipeline builds. Step 30 adds the Router CA for
# GITLAB_REGISTRY_HOST to image.config.openshift.io/cluster additionalTrustedCA
# (no node reboot); 39-teardown removes it again.
export REGISTRY_CA_CONFIGMAP="ked-demo-registry-ca"     # in openshift-config (if none set yet)
export REGISTRY_CA_ANNOTATION="ked-demo/registry-ca"

# ── Build & deploy pipeline (step 32) ────────────────────────────────────────
export PIPELINE_NAME="build-deploy"
export MAVEN_CACHE_PVC="maven-repo"          # persistent Maven local repo (RWO)
export MAVEN_CACHE_SIZE="2Gi"
export REGISTRY_SECRET="gitlab-registry"     # dockerconfigjson: push (cicd) + pull (dev)
export APP_IMAGE_REPO=""                     # empty → <registry-host>/<group>/<project>

# ── Red Hat Advanced Cluster Security (steps 32, 34) ─────────────────────────
# Central runs outside the cluster (ACS Cloud Service); this cluster is a
# SecuredCluster with a local scanner → images in the in-cluster GitLab
# registry are scanned with DELEGATED scanning (the cloud cannot reach them).
# The Central URL and API token are NOT stored here: put them in KEYS_FILE
# (git-ignored) as
#   acs_url:https://<central-host>
#   acs:<token>
export ACS_CENTRAL_URL="${ACS_CENTRAL_URL:-}" # empty → '<ACS_URL_KEY>:' in KEYS_FILE
export ACS_CLUSTER=""                        # empty → SecuredCluster spec.clusterName
export ACS_URL_KEY="acs_url"                 # key in KEYS_FILE
export ACS_TOKEN_KEY="acs"                   # key in KEYS_FILE
export ACS_SECRET="rox-auth"                 # Secret in CICD_PROJECT (endpoint, token, cluster)
export ACS_REGISTRY_INTEGRATION="ked-demo-gitlab"   # ACS image integration for the GitLab registry
export KEYS_FILE="keys.txt"                  # repo-root relative, lines "name:value"

# ── ACS gate demo (step 34) ──────────────────────────────────────────────────
# A developer commits a vulnerable dependency (Log4Shell) → the existing
# build-enforced policy on Central stops the pipeline → revert → green again.
export ACS_GATE_POLICY="Fixable Severity at least Important"   # FAIL_BUILD_ENFORCEMENT on Central
export VULN_DEP_GROUP="org.apache.logging.log4j"
export VULN_DEP_ARTIFACT="log4j-core"
export VULN_DEP_VERSION="2.14.1"             # CVE-2021-44228 (Log4Shell), CRITICAL, fixable
export VULN_COMMIT_MSG="Add log4j-core for file logging"
export VULN_COMMIT_AUTHOR="Dev Eloper"
export VULN_COMMIT_EMAIL="dev@ked.local"

# ── Pipelines-as-Code (step 35) ──────────────────────────────────────────────
# GitLab → webhook → PAC controller → PipelineRun from the app repo's .tekton/.
# Both directions use in-cluster Services (no self-signed Route certificate):
#   GitLab webhook → PAC_WEBHOOK_URL ; PAC → GitLab API at PAC_GITLAB_API_URL
export PAC_SECRET="gitlab-pac"               # provider.token + webhook.secret (CICD_PROJECT)
export PAC_WEBHOOK_URL="http://pipelines-as-code-controller.${TEKTON_NAMESPACE}.svc.cluster.local:8080"
export PAC_GITLAB_API_URL="http://gitlab.${GITLAB_NAMESPACE}.svc.cluster.local"
export PAC_MR_BRANCH="feature/file-logging"
export PAC_MR_TITLE="Add file logging (log4j)"

# ── OpenShift GitOps / Argo CD (steps 36–38) ─────────────────────────────────
# Default cluster-scoped instance + own AppProject. Desired state of the dev
# environment lives in a separate GitLab project (Kustomize base + overlay);
# the pipeline commits the image digest there and Argo CD syncs ocp-demo-dev.
export ARGO_NAMESPACE="openshift-gitops"
export ARGO_PROJECT="ked-demo"               # AppProject
export ARGO_APP="${APP_NAME}-dev"            # Application
export GITOPS_PROJECT="${APP_NAME}-gitops"   # GitLab project in GITLAB_GROUP
export GITOPS_SEED_DIR="cicd/gitops/${APP_NAME}"   # repo-relative manifests seeded into it
export GITOPS_OVERLAY="overlays/dev"
export GITOPS_TOKEN_NAME="tekton-gitops"     # project token (write) of the gitops repo
export GITOPS_SECRET="gitops-repo-auth"      # Secret in CICD_PROJECT (username, password)
export GITOPS_IMAGE="registry.redhat.io/openshift-gitops-1/argocd-rhel9:v1.22.2"   # git + kustomize
export ARGO_WEBHOOK_URL="https://openshift-gitops-server.${ARGO_NAMESPACE}.svc.cluster.local/api/webhook"

# -----------------------------------------------------------------------------
# COLORS — for pretty terminal output during demo
# -----------------------------------------------------------------------------
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export CYAN='\033[0;36m'
export BOLD='\033[1m'
export RESET='\033[0m'

# -----------------------------------------------------------------------------
# HELPER FUNCTIONS
# -----------------------------------------------------------------------------

# Print a section header
header() {
  echo ""
  echo -e "${CYAN}${BOLD}══════════════════════════════════════════════${RESET}"
  echo -e "${CYAN}${BOLD}  $1${RESET}"
  echo -e "${CYAN}${BOLD}══════════════════════════════════════════════${RESET}"
  echo ""
}

# Print a step
step() {
  echo -e "${YELLOW}▶ $1${RESET}"
}

# Print success
ok() {
  echo -e "${GREEN}✔ $1${RESET}"
}

# Print warning
warn() {
  echo -e "${RED}⚠ $1${RESET}"
}

# Wait for user to press Enter (pacing during live demo)
pause() {
  echo ""
  echo -e "${BOLD}[Press ENTER to continue...]${RESET}"
  read -r
}

# Wait for a deployment to be ready
wait_for_deployment() {
  local name=$1
  local ns=${2:-$DEMO_PROJECT}
  step "Waiting for deployment/${name} to be ready..."
  oc rollout status deployment/"${name}" -n "${ns}" --timeout=300s
  ok "deployment/${name} is ready"
}

# Wait for a pod label to be running
wait_for_pods() {
  local selector=$1
  local ns=${2:-$DEMO_PROJECT}
  step "Waiting for pods (${selector}) to be Running..."
  oc wait pod -l "${selector}" -n "${ns}" \
    --for=condition=Ready \
    --timeout=300s
  ok "Pods are ready"
}

# Show a command (or YAML block) before executing — gives presenter time to explain
# Usage:  show_cmd "oc new-app ..."
show_cmd() {
  local _B=$'\033[1m' _Y=$'\033[1;33m' _C=$'\033[0;36m' _R=$'\033[0m'
  printf "\n"
  printf "%s┌─ Command ────────────────────────────────────────────────────┐%s\n" "${_B}${_Y}" "${_R}"
  while IFS= read -r line; do
    printf "%s│%s  %s%s%s\n" "${_B}${_Y}" "${_R}" "${_C}" "${line}" "${_R}"
  done <<< "$1"
  printf "%s└──────────────────────────────────────────────────────────────┘%s\n" "${_B}${_Y}" "${_R}"
  printf "\n"
  printf "%s[Press ENTER to run ↑]%s " "${_B}" "${_R}"
  read -r < /dev/tty
}

# Check oc is logged in
check_login() {
  if ! oc whoami &>/dev/null; then
    warn "Not logged in to OpenShift. Run: oc login ${OCP_API_URL}"
    exit 1
  fi
  ok "Logged in as: $(oc whoami)"
}

# Ensure we're in the right project
use_project() {
  oc project "${DEMO_PROJECT}" &>/dev/null || \
    oc new-project "${DEMO_PROJECT}" --display-name="${DEMO_PROJECT_DISPLAY}"
  ok "Using project: ${DEMO_PROJECT}"
}

# Return the cluster's wildcard apps domain (e.g. apps.cluster.example.com)
# Used to build Route hostnames.
get_apps_domain() {
  oc get ingresses.config.openshift.io cluster \
    -o jsonpath='{.spec.domain}' 2>/dev/null
}

# Return the domain used for Gateway API listener/route hostnames in ACT 4.
# Precedence:
#   1. GATEWAY_DOMAIN if explicitly set in this config
#   2. The apps domain with its leading "apps." replaced by "api."
#      (e.g. apps.mini.example.com -> api.mini.example.com)
get_gateway_domain() {
  if [[ -n "${GATEWAY_DOMAIN:-}" ]]; then
    echo "${GATEWAY_DOMAIN}"
    return
  fi
  local apps_domain
  apps_domain="$(get_apps_domain)"
  if [[ -n "${apps_domain}" ]]; then
    echo "${apps_domain/#apps./api.}"
  fi
}

# ACT 5 — GitLab web/API hostname (GITLAB_HOST or gitlab.<apps-domain>)
get_gitlab_host() {
  if [[ -n "${GITLAB_HOST:-}" ]]; then
    echo "${GITLAB_HOST}"
  else
    echo "gitlab.$(get_apps_domain)"
  fi
}

# ACT 5 — GitLab Container Registry hostname (GITLAB_REGISTRY_HOST or registry.<apps-domain>)
get_gitlab_registry_host() {
  if [[ -n "${GITLAB_REGISTRY_HOST:-}" ]]; then
    echo "${GITLAB_REGISTRY_HOST}"
  else
    echo "registry.$(get_apps_domain)"
  fi
}

# ACT 5 — StorageClass for PVCs: STORAGE_CLASS, else the cluster default SC,
# else the first SC found (some clusters have no default SC annotated)
get_storage_class() {
  if [[ -n "${STORAGE_CLASS:-}" ]]; then
    echo "${STORAGE_CLASS}"
    return
  fi
  local sc
  sc="$(oc get storageclass -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | head -1)"
  [[ -n "${sc}" ]] || sc="$(oc get storageclass -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)"
  echo "${sc}"
}

# ACT 5 — read one key from the GitLab credentials Secret (empty if missing)
get_gitlab_cred() {
  oc get secret "${GITLAB_CREDS_SECRET}" -n "${GITLAB_NAMESPACE}" \
    -o jsonpath="{.data.$1}" 2>/dev/null | base64 -d 2>/dev/null || true
}

# ACT 5 — read "name:value" from the git-ignored KEYS_FILE (empty if missing)
get_key() {
  local file="${KEYS_FILE}"
  [[ "${file}" = /* ]] || file="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/${file}"
  [[ -f "${file}" ]] || return 0
  sed -n "s/^$1:[[:space:]]*//p" "${file}" | head -1 | tr -d '\r\n '
}
[[ -n "${ACS_CENTRAL_URL}" ]] || ACS_CENTRAL_URL="$(get_key "${ACS_URL_KEY}")"

# ACT 5 — image repository the pipeline pushes to
get_app_image_repo() {
  if [[ -n "${APP_IMAGE_REPO:-}" ]]; then
    echo "${APP_IMAGE_REPO}"
  else
    echo "$(get_gitlab_registry_host)/${GITLAB_GROUP}/${GITLAB_PROJECT}"
  fi
}

# ACT 5 — ACS cluster name (ACS_CLUSTER or the local SecuredCluster's clusterName)
get_acs_cluster() {
  if [[ -n "${ACS_CLUSTER:-}" ]]; then
    echo "${ACS_CLUSTER}"
  else
    oc get securedcluster -A -o jsonpath='{.items[0].spec.clusterName}' 2>/dev/null
  fi
}

# ACT 5 — gitops repo URLs: public (Argo CD, browser) and in-cluster (pipeline push)
get_gitops_repo_url() { echo "https://$(get_gitlab_host)/${GITLAB_GROUP}/${GITOPS_PROJECT}.git"; }
get_gitops_repo_internal() { echo "${PAC_GITLAB_API_URL}/${GITLAB_GROUP}/${GITOPS_PROJECT}.git"; }

# ACT 5 — true once the Argo CD Application for the dev environment exists (step 36)
argo_enabled() {
  oc get applications.argoproj.io "${ARGO_APP}" -n "${ARGO_NAMESPACE}" &>/dev/null
}

# ACT 5 — how the pipeline delivers: "oc" (steps 32–35) or "gitops" (step 37+)
get_deploy_mode() { if argo_enabled; then echo gitops; else echo oc; fi; }

# ACT 5 — start the build-deploy pipeline and stream its logs (steps 32, 34).
# Never fails: callers check the outcome with last_build_run / oc get.
start_build_run() {
  local repo_root
  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  tkn pipeline start "${PIPELINE_NAME}" -n "${CICD_PROJECT}" \
    -p git-url="https://$(get_gitlab_host)/${GITLAB_GROUP}/${GITLAB_PROJECT}.git" \
    -p image-repo="$(get_app_image_repo)" \
    -p dev-namespace="${DEV_PROJECT}" -p app-name="${APP_NAME}" \
    -p deploy-mode="$(get_deploy_mode)" -p gitops-repo="$(get_gitops_repo_internal)" \
    -w name=source,volumeClaimTemplateFile="${repo_root}/cicd/tekton/intro/workspace-template.yaml" \
    -w name=maven-repo,claimName="${MAVEN_CACHE_PVC}" \
    -w name=registry-auth,secret="${REGISTRY_SECRET}" \
    --use-param-defaults --showlog || true
}

# ACT 5 — name of the most recent build-deploy PipelineRun
last_build_run() {
  oc get pipelinerun -n "${CICD_PROJECT}" -l "tekton.dev/pipeline=${PIPELINE_NAME}" \
    --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].metadata.name}'
}

# ACT 5 — true if a PipelineRun succeeded (reason is "Succeeded", or
# "Completed" when some tasks were skipped by `when` expressions)
run_succeeded() {
  [[ "$(oc get pipelinerun "$1" -n "${CICD_PROJECT}" -o jsonpath='{.status.conditions[0].status}' 2>/dev/null)" == "True" ]]
}

# ACT 5 — true if Pipelines-as-Code is connected (Repository CR exists)
pac_enabled() {
  [[ -n "$(oc get repositories.pipelinesascode.tekton.dev -n "${CICD_PROJECT}" -o name 2>/dev/null)" ]]
}

# ACT 5 — wait for the PipelineRun that Pipelines-as-Code creates for a commit
# SHA, stream its logs until it finishes; sets PAC_RUN (empty on timeout)
wait_pac_run() {
  local sha="$1"
  PAC_RUN=""
  echo -e "  Waiting for Pipelines-as-Code to start a PipelineRun for ${sha:0:8}..."
  for _ in $(seq 1 90); do
    PAC_RUN="$(oc get pipelinerun -n "${CICD_PROJECT}" -l "pipelinesascode.tekton.dev/sha=${sha}" \
      --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].metadata.name}' 2>/dev/null || true)"
    [[ -n "${PAC_RUN}" ]] && break
    sleep 2
  done
  [[ -n "${PAC_RUN}" ]] || { echo "  (no PipelineRun after 3 min — check the GitLab webhook / PAC controller logs)"; return 0; }
  echo -e "  PipelineRun started by the webhook: ${PAC_RUN}"
  tkn pipelinerun logs "${PAC_RUN}" -n "${CICD_PROJECT}" -f || true
  for _ in $(seq 1 60); do
    [[ -n "$(oc get pipelinerun "${PAC_RUN}" -n "${CICD_PROJECT}" -o jsonpath='{.status.completionTime}' 2>/dev/null)" ]] && break
    sleep 2
  done
}

#!/usr/bin/env bash
# =============================================================================
# 30-gitlab-setup.sh — ACT 5 PRE-DEMO: PostgreSQL 17 + GitLab Omnibus + app repo
#                       (+ OpenShift Pipelines coschedule prep, ACS Scanner V4 check)
#
# Run BEFORE the session (first boot takes ~5–10 min). Not presented live, so
# no show_cmd/pause — same style as 00-setup.sh.
#
# Idempotent: re-running re-applies the manifests and reuses the existing
# credentials, group, project and token. The app repo is seeded only while it
# is empty; set GITLAB_RESEED=1 to force-push app/ocp-demo-app again.
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/demo-config.sh"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="${REPO_ROOT}/cicd/gitlab/gitlab-omnibus.yaml"
PG_MANIFEST="${REPO_ROOT}/cicd/gitlab/gitlab-postgresql.yaml"
ADMIN_TOKEN_NAME="ked-demo-admin"

header "ACT 5 — Pre-demo: GitLab (Omnibus) in the cluster"

check_login
for bin in curl jq git envsubst; do
  command -v "${bin}" &>/dev/null || { warn "'${bin}' not found in PATH"; exit 1; }
done

APPS_DOMAIN="$(get_apps_domain)"
[[ -n "${APPS_DOMAIN}" ]] || { warn "Could not detect the cluster apps domain"; exit 1; }
export GITLAB_HOST GITLAB_REGISTRY_HOST GITLAB_STORAGE_CLASS GITLAB_POSTGRES_IMAGE
GITLAB_HOST="$(get_gitlab_host)"
GITLAB_REGISTRY_HOST="$(get_gitlab_registry_host)"
GITLAB_STORAGE_CLASS="$(get_storage_class)"
[[ -n "${GITLAB_STORAGE_CLASS}" ]] || { warn "No StorageClass found — set STORAGE_CLASS in demo-config.sh"; exit 1; }
GL_URL="https://${GITLAB_HOST}"
API="${GL_URL}/api/v4"

# 24 random alphanumerics (cut reads all input → no SIGPIPE under pipefail)
gen_secret() { head -c 96 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | cut -c1-24; }

set_cred() {
  oc patch secret "${GITLAB_CREDS_SECRET}" -n "${GITLAB_NAMESPACE}" --type merge \
    -p "$(jq -nc --arg k "$1" --arg v "$2" '{stringData: {($k): $v}}')" >/dev/null
}

http_code() { curl -sk -o /dev/null -w '%{http_code}' "$@"; }

token_ok() { [[ -n "$1" && "$(http_code -H "PRIVATE-TOKEN: $1" "${API}/user")" == "200" ]]; }

gl_api() {
  local method="$1" path="$2"; shift 2
  curl -sk -X "${method}" -H "PRIVATE-TOKEN: ${ROOT_TOKEN}" "${API}${path}" "$@"
}

echo -e "  ${BOLD}Namespace :${RESET} ${CYAN}${GITLAB_NAMESPACE}${RESET}"
echo -e "  ${BOLD}Image     :${RESET} ${CYAN}${GITLAB_IMAGE}${RESET}"
echo -e "  ${BOLD}Database  :${RESET} ${CYAN}${GITLAB_POSTGRES_IMAGE}${RESET}"
echo -e "  ${BOLD}GitLab    :${RESET} ${CYAN}${GL_URL}${RESET}"
echo -e "  ${BOLD}Registry  :${RESET} ${CYAN}https://${GITLAB_REGISTRY_HOST}${RESET}"
echo -e "  ${BOLD}Storage   :${RESET} ${CYAN}${GITLAB_STORAGE_CLASS}${RESET}"
echo ""

# ── Step 1: Namespace + anyuid SCC (Omnibus runs as root) ────────────────────
step "Ensuring namespace '${GITLAB_NAMESPACE}'..."
oc get project "${GITLAB_NAMESPACE}" &>/dev/null || \
  oc new-project "${GITLAB_NAMESPACE}" --display-name="GitLab (demo)" --skip-config-write >/dev/null
oc adm policy add-scc-to-user anyuid -z gitlab -n "${GITLAB_NAMESPACE}" >/dev/null
ok "Namespace ready, ServiceAccount 'gitlab' allowed to use the anyuid SCC"

# ── Step 2: Credentials Secret (each password generated once) ────────────────
step "Ensuring credentials Secret '${GITLAB_CREDS_SECRET}'..."
oc get secret "${GITLAB_CREDS_SECRET}" -n "${GITLAB_NAMESPACE}" &>/dev/null || \
  oc create secret generic "${GITLAB_CREDS_SECRET}" -n "${GITLAB_NAMESPACE}" >/dev/null
for key in root-password db-password registry-db-password; do
  if [[ -z "$(get_gitlab_cred "${key}")" ]]; then
    set_cred "${key}" "$(gen_secret)"
    ok "Generated '${key}'"
  else
    ok "Reusing '${key}'"
  fi
done

# storageClassName is immutable: re-create only never-bound PVCs left with
# another SC (the owning Deployment is removed first so the PVC can go away)
recreate_stale_pvcs() {
  local deploy="$1" label="$2"; shift 2
  local stale=() pvc phase sc
  for pvc in "$@"; do
    read -r phase sc < <(oc get pvc "${pvc}" -n "${GITLAB_NAMESPACE}" \
      -o jsonpath='{.status.phase} {.spec.storageClassName}{"\n"}' 2>/dev/null || echo "")
    if [[ "${phase:-}" == "Pending" && "${sc:-}" != "${GITLAB_STORAGE_CLASS}" ]]; then
      stale+=("${pvc}")
    fi
  done
  if (( ${#stale[@]} > 0 )); then
    warn "Re-creating unbound PVC(s) ${stale[*]} with StorageClass '${GITLAB_STORAGE_CLASS}'"
    oc delete deployment "${deploy}" -n "${GITLAB_NAMESPACE}" --ignore-not-found --wait=true >/dev/null
    oc wait pod -l "${label}" -n "${GITLAB_NAMESPACE}" --for=delete --timeout=120s &>/dev/null || true
    oc delete pvc "${stale[@]}" -n "${GITLAB_NAMESPACE}" --wait=true >/dev/null
  fi
}

render() {
  envsubst '${GITLAB_NAMESPACE} ${GITLAB_IMAGE} ${GITLAB_POSTGRES_IMAGE} ${GITLAB_HOST} ${GITLAB_REGISTRY_HOST} ${GITLAB_CREDS_SECRET} ${GITLAB_STORAGE_CLASS}' < "$1"
}

# ── Step 3: PostgreSQL 17 first — GitLab connects to it ──────────────────────
step "Applying cicd/gitlab/gitlab-postgresql.yaml (init ConfigMap, PVC, Deployment, Service)..."
recreate_stale_pvcs gitlab-postgresql app=gitlab-postgresql gitlab-postgresql
render "${PG_MANIFEST}" | oc apply -f -

step "Waiting for PostgreSQL to be ready..."
oc rollout status deployment/gitlab-postgresql -n "${GITLAB_NAMESPACE}" --timeout=300s
oc exec -n "${GITLAB_NAMESPACE}" deploy/gitlab-postgresql -- \
  psql -U gitlab -d gitlabhq_production -tAc 'select version();'
DBS="$(oc exec -n "${GITLAB_NAMESPACE}" deploy/gitlab-postgresql -- \
  psql -U gitlab -d postgres -tAc "select string_agg(datname, ',' order by datname) from pg_database where datname in ('gitlabhq_production','registry');")"
[[ "${DBS}" == "gitlabhq_production,registry" ]] || { warn "Expected databases missing (found: ${DBS})"; exit 1; }
ok "PostgreSQL ready — databases: gitlabhq_production (Rails), registry (Container Registry)"

# ── Step 4: Deploy GitLab Omnibus (bundled PostgreSQL disabled) ──────────────
step "Applying cicd/gitlab/gitlab-omnibus.yaml (SA, PVCs, Deployment, Service, Routes)..."
recreate_stale_pvcs gitlab app=gitlab gitlab-config gitlab-logs gitlab-data
render "${MANIFEST}" | oc apply -f -

step "Waiting for GitLab to become ready (first boot ≈ 5–10 min)..."
oc rollout status deployment/gitlab -n "${GITLAB_NAMESPACE}" --timeout=1200s
for _ in $(seq 1 60); do
  [[ "$(http_code "${GL_URL}/users/sign_in")" == "200" ]] && break
  sleep 5
done
[[ "$(http_code "${GL_URL}/users/sign_in")" == "200" ]] || { warn "GitLab Route not answering at ${GL_URL}"; exit 1; }
ok "GitLab is up at ${GL_URL}"

# ── Step 5: Admin API token for root (minted via gitlab-rails, once) ─────────
step "Ensuring root API token '${ADMIN_TOKEN_NAME}'..."
ROOT_TOKEN="$(get_gitlab_cred root-token)"
if token_ok "${ROOT_TOKEN}"; then
  ok "Reusing existing root token"
else
  ROOT_TOKEN="glpat-$(gen_secret)"
  echo "  Minting a new token via gitlab-rails runner (takes ~1 min)..."
  oc exec -i -n "${GITLAB_NAMESPACE}" deploy/gitlab -- gitlab-rails runner - <<RUBY
user = User.find_by_username('root')
user.personal_access_tokens.active.where(name: '${ADMIN_TOKEN_NAME}').each(&:revoke!)
token = user.personal_access_tokens.build(
  name: '${ADMIN_TOKEN_NAME}',
  scopes: [:api, :read_repository, :write_repository],
  expires_at: 364.days.from_now
)
token.set_token('${ROOT_TOKEN}')
token.save!
puts 'token created'
RUBY
  token_ok "${ROOT_TOKEN}" || { warn "The new root token is not accepted by the API"; exit 1; }
  set_cred root-token "${ROOT_TOKEN}"
  ok "Root token created and stored in Secret '${GITLAB_CREDS_SECRET}'"
fi

# ── Step 6: Instance settings needed by the demo ─────────────────────────────
# - webhooks to in-cluster/private addresses (Pipelines-as-Code controller)
# - no Auto DevOps: GitLab CI is not used, Tekton reports the pipeline status
# - no public sign-up
step "Configuring instance settings (local webhooks, no Auto DevOps, no sign-up)..."
gl_api PUT /application/settings \
  --data allow_local_requests_from_web_hooks_and_services=true \
  --data allow_local_requests_from_system_hooks=true \
  --data auto_devops_enabled=false \
  --data signup_enabled=false >/dev/null
ok "Instance settings applied"

# ── Step 7: Group + project ──────────────────────────────────────────────────
step "Ensuring group '${GITLAB_GROUP}'..."
GROUP_ID="$(gl_api GET "/groups/${GITLAB_GROUP}" | jq -r '.id // empty')"
if [[ -z "${GROUP_ID}" ]]; then
  GROUP_ID="$(gl_api POST /groups \
    --data name="${GITLAB_GROUP}" --data path="${GITLAB_GROUP}" \
    --data visibility=public | jq -r '.id // empty')"
fi
[[ -n "${GROUP_ID}" ]] || { warn "Group create/lookup failed"; exit 1; }
ok "Group '${GITLAB_GROUP}' (id=${GROUP_ID})"

step "Ensuring project '${GITLAB_GROUP}/${GITLAB_PROJECT}'..."
PROJECT_ENC="${GITLAB_GROUP}%2F${GITLAB_PROJECT}"
PROJECT_ID="$(gl_api GET "/projects/${PROJECT_ENC}" | jq -r '.id // empty')"
if [[ -z "${PROJECT_ID}" ]]; then
  PROJECT_ID="$(gl_api POST /projects \
    --data name="${GITLAB_PROJECT}" --data path="${GITLAB_PROJECT}" \
    --data namespace_id="${GROUP_ID}" --data visibility=public \
    --data initialize_with_readme=false | jq -r '.id // empty')"
fi
[[ -n "${PROJECT_ID}" ]] || { warn "Project create/lookup failed"; exit 1; }
ok "Project '${GITLAB_GROUP}/${GITLAB_PROJECT}' (id=${PROJECT_ID})"

# ── Step 8: Seed the app repo from app/ocp-demo-app ──────────────────────────
step "Seeding the app repo from '${GITLAB_SEED_DIR}'..."
EMPTY_REPO="$(gl_api GET "/projects/${PROJECT_ID}" | jq -r '.empty_repo')"
if [[ "${EMPTY_REPO}" == "true" || "${GITLAB_RESEED:-0}" == "1" ]]; then
  SEED_TMP="$(mktemp -d)"
  trap 'rm -rf "${SEED_TMP}"' EXIT
  tar -C "${REPO_ROOT}/${GITLAB_SEED_DIR}" --exclude=./target --exclude=./.quarkus -cf - . \
    | tar -C "${SEED_TMP}" -xf -
  git -C "${SEED_TMP}" init -q -b main
  git -C "${SEED_TMP}" add -A
  git -C "${SEED_TMP}" -c user.name="KED Demo" -c user.email="demo@ked.local" \
    commit -q -m "Import ${GITLAB_PROJECT} from ${GIT_REPO} (${GITLAB_SEED_DIR})"

  PUSH_FLAGS=()
  if [[ "${EMPTY_REPO}" != "true" ]]; then
    gl_api PATCH "/projects/${PROJECT_ID}/protected_branches/main" \
      --data allow_force_push=true >/dev/null
    PUSH_FLAGS=(--force)
  fi
  # Credentials via env (not argv / not stored in the temp repo config)
  GIT_CONFIG_COUNT=2 \
  GIT_CONFIG_KEY_0="http.extraHeader" \
  GIT_CONFIG_VALUE_0="Authorization: Basic $(printf 'oauth2:%s' "${ROOT_TOKEN}" | base64 -w0)" \
  GIT_CONFIG_KEY_1="http.sslVerify" \
  GIT_CONFIG_VALUE_1="false" \
    git -C "${SEED_TMP}" push -q "${PUSH_FLAGS[@]}" \
      "${GL_URL}/${GITLAB_GROUP}/${GITLAB_PROJECT}.git" main
  ok "Pushed ${GITLAB_SEED_DIR} → ${GL_URL}/${GITLAB_GROUP}/${GITLAB_PROJECT}"
else
  ok "Repo already has commits — skipped (GITLAB_RESEED=1 to force-push again)"
fi

# ── Step 9: Project access token for Tekton (clone, push image, PAC status) ──
step "Ensuring project access token '${GITLAB_CI_TOKEN_NAME}'..."
CI_TOKEN="$(get_gitlab_cred ci-token)"
CI_USER="$(get_gitlab_cred ci-username)"
if [[ -n "${CI_USER}" ]] && \
   [[ "$(http_code -H "PRIVATE-TOKEN: ${CI_TOKEN}" "${API}/projects/${PROJECT_ID}")" == "200" ]]; then
  ok "Reusing existing CI token (user '${CI_USER}')"
else
  for tid in $(gl_api GET "/projects/${PROJECT_ID}/access_tokens?state=active" \
                 | jq -r --arg n "${GITLAB_CI_TOKEN_NAME}" '.[] | select(.name == $n) | .id'); do
    gl_api DELETE "/projects/${PROJECT_ID}/access_tokens/${tid}" >/dev/null
  done
  TOKEN_JSON="$(gl_api POST "/projects/${PROJECT_ID}/access_tokens" \
    -H 'Content-Type: application/json' \
    --data "$(jq -nc --arg n "${GITLAB_CI_TOKEN_NAME}" --arg e "$(date -d '+364 days' +%F)" '{
      name: $n, access_level: 40, expires_at: $e,
      scopes: ["api", "read_repository", "write_repository", "read_registry", "write_registry"]}')")"
  CI_TOKEN="$(jq -r '.token // empty' <<< "${TOKEN_JSON}")"
  CI_USER_ID="$(jq -r '.user_id // empty' <<< "${TOKEN_JSON}")"
  [[ -n "${CI_TOKEN}" && -n "${CI_USER_ID}" ]] || { warn "CI token creation failed: ${TOKEN_JSON}"; exit 1; }
  CI_USER="$(gl_api GET "/users/${CI_USER_ID}" | jq -r '.username')"
  set_cred ci-token "${CI_TOKEN}"
  set_cred ci-username "${CI_USER}"
  ok "CI token created for bot user '${CI_USER}' (Maintainer, api + registry scopes)"
fi

# ── Step 10: OpenShift Pipelines — affinity assistant coschedule mode ────────
# Cluster-wide prep for step 32 (source + Maven cache = 2 PVC workspaces in
# one TaskRun). The original value is recorded once so 39-teardown restores it.
step "Setting Tekton affinity assistant coschedule='${TEKTON_COSCHEDULE}' (TektonConfig 'config')..."
oc get tektonconfig config &>/dev/null || { warn "TektonConfig 'config' not found — is OpenShift Pipelines installed?"; exit 1; }
CUR_COSCHEDULE="$(oc get tektonconfig config -o jsonpath='{.spec.pipeline.coschedule}')"
if [[ "${CUR_COSCHEDULE}" == "${TEKTON_COSCHEDULE}" ]]; then
  ok "Already '${TEKTON_COSCHEDULE}'"
else
  ORIG_COSCHEDULE="$(oc get tektonconfig config -o json \
    | jq -r --arg a "${TEKTON_COSCHEDULE_ANNOTATION}" '.metadata.annotations[$a] // empty')"
  [[ -n "${ORIG_COSCHEDULE}" ]] || \
    oc annotate tektonconfig config "${TEKTON_COSCHEDULE_ANNOTATION}=${CUR_COSCHEDULE:-workspaces}" --overwrite >/dev/null
  oc patch tektonconfig config --type merge \
    -p "{\"spec\":{\"pipeline\":{\"coschedule\":\"${TEKTON_COSCHEDULE}\"}}}" >/dev/null
  ok "Changed '${CUR_COSCHEDULE:-workspaces}' → '${TEKTON_COSCHEDULE}' (original kept in annotation ${TEKTON_COSCHEDULE_ANNOTATION})"
fi
for _ in $(seq 1 60); do
  FLAG="$(oc get cm feature-flags -n "${TEKTON_NAMESPACE}" -o jsonpath='{.data.coschedule}' 2>/dev/null || true)"
  [[ "${FLAG}" == "${TEKTON_COSCHEDULE}" ]] && break
  sleep 2
done
[[ "${FLAG}" == "${TEKTON_COSCHEDULE}" ]] \
  && ok "Pipelines controller feature-flags: coschedule=${FLAG}" \
  || { warn "feature-flags still report coschedule='${FLAG}' — check the TektonConfig status"; exit 1; }

# ── Step 11: Nodes trust the GitLab registry (image pulls) ───────────────────
# The Router certificate is signed by the ingress-operator CA, unknown to
# CRI-O → ImagePullBackOff "x509: certificate signed by unknown authority".
# additionalTrustedCA takes a ConfigMap keyed by registry hostname.
step "Trusting the Router CA for image pulls from '${GITLAB_REGISTRY_HOST}' (image.config cluster)..."
INGRESS_CA="$(oc get cm default-ingress-cert -n openshift-config-managed -o jsonpath='{.data.ca-bundle\.crt}')"
[[ -n "${INGRESS_CA}" ]] || { warn "Router CA (openshift-config-managed/default-ingress-cert) not found"; exit 1; }
CA_CM="$(oc get image.config.openshift.io cluster -o jsonpath='{.spec.additionalTrustedCA.name}')"
CA_CHANGED=false
if [[ -z "${CA_CM}" ]]; then
  CA_CHANGED=true
  CA_CM="${REGISTRY_CA_CONFIGMAP}"
  oc annotate image.config.openshift.io cluster "${REGISTRY_CA_ANNOTATION}=${CA_CM}" --overwrite >/dev/null
fi
oc get cm "${CA_CM}" -n openshift-config &>/dev/null || oc create cm "${CA_CM}" -n openshift-config >/dev/null
if [[ "$(oc get cm "${CA_CM}" -n openshift-config -o json | jq -r --arg k "${GITLAB_REGISTRY_HOST}" '.data[$k] // empty')" == "${INGRESS_CA}" ]]; then
  ok "ConfigMap openshift-config/${CA_CM} already has the CA for '${GITLAB_REGISTRY_HOST}'"
else
  oc patch cm "${CA_CM}" -n openshift-config --type merge \
    -p "$(jq -nc --arg k "${GITLAB_REGISTRY_HOST}" --arg v "${INGRESS_CA}" '{data: {($k): $v}}')" >/dev/null
  CA_CHANGED=true
  [[ "${CA_CM}" == "${REGISTRY_CA_CONFIGMAP}" ]] || \
    oc annotate cm "${CA_CM}" -n openshift-config "${REGISTRY_CA_ANNOTATION}-key=${GITLAB_REGISTRY_HOST}" --overwrite >/dev/null
  ok "Router CA stored in ConfigMap openshift-config/${CA_CM} (key '${GITLAB_REGISTRY_HOST}')"
fi
oc patch image.config.openshift.io cluster --type merge \
  -p "{\"spec\":{\"additionalTrustedCA\":{\"name\":\"${CA_CM}\"}}}" >/dev/null
ok "image.config cluster → additionalTrustedCA '${CA_CM}' (propagated to the nodes, no reboot)"
if [[ "${CA_CHANGED}" == true ]]; then
  # openshift-apiserver restarts to pick up the CA (≈1–2 min API blip on SNO)
  step "Waiting for openshift-apiserver to roll out the new CA..."
  sleep 20
  for _ in $(seq 1 60); do
    [[ "$(oc get co openshift-apiserver -o jsonpath='{.status.conditions[?(@.type=="Available")].status}{.status.conditions[?(@.type=="Progressing")].status}' 2>/dev/null)" == "TrueFalse" ]] && break
    sleep 5
  done
  ok "openshift-apiserver available"
fi

# ── Step 12: ACS Scanner V4 schema (image scans in steps 32–37) ──────────────
# Same guard 32/34 run before every pipeline — done here too so a lost
# scanner-v4-db schema (e.g. after a node reboot) is fixed before the session.
step "Checking ACS Scanner V4 (indexer schema vs. scanner-v4-db)..."
ensure_acs_scanner_ready

# ── Step 13: Verify ───────────────────────────────────────────────────────────
step "Verifying..."
RAILS_TABLES="$(oc exec -n "${GITLAB_NAMESPACE}" deploy/gitlab-postgresql -- \
  psql -U gitlab -d gitlabhq_production -tAc "select count(*) from information_schema.tables where table_schema='public';")"
REG_TABLES="$(oc exec -n "${GITLAB_NAMESPACE}" deploy/gitlab-postgresql -- \
  psql -U gitlab -d registry -tAc "select count(*) from information_schema.tables where table_schema='public';")"
ok "External PostgreSQL in use — gitlabhq_production: ${RAILS_TABLES} tables, registry: ${REG_TABLES} tables"
if oc exec -n "${GITLAB_NAMESPACE}" deploy/gitlab -- gitlab-ctl status 2>/dev/null | grep -q '^run: postgresql'; then
  warn "Bundled PostgreSQL is running inside the GitLab pod (expected: disabled)"
else
  ok "Bundled PostgreSQL disabled in the GitLab pod"
fi
REG_CODE="$(http_code "https://${GITLAB_REGISTRY_HOST}/v2/")"
[[ "${REG_CODE}" == "401" ]] \
  && ok "Container Registry answers (HTTP 401 = auth required, as expected)" \
  || warn "Container Registry returned HTTP ${REG_CODE} (expected 401)"
oc get deploy,svc,route,pvc -n "${GITLAB_NAMESPACE}"
echo ""

echo -e "${GREEN}${BOLD}GitLab is ready for ACT 5.${RESET}"
echo -e "  ${BOLD}Web UI   :${RESET} ${CYAN}${GL_URL}${RESET}  (user: root)"
echo -e "  ${BOLD}App repo :${RESET} ${CYAN}${GL_URL}/${GITLAB_GROUP}/${GITLAB_PROJECT}${RESET}"
echo -e "  ${BOLD}Registry :${RESET} ${CYAN}${GITLAB_REGISTRY_HOST}/${GITLAB_GROUP}/${GITLAB_PROJECT}${RESET}"
echo -e "  ${BOLD}Root pwd :${RESET} oc get secret ${GITLAB_CREDS_SECRET} -n ${GITLAB_NAMESPACE} -o jsonpath='{.data.root-password}' | base64 -d"
echo ""
warn "The Router certificate is self-signed — browsers will warn, CLI tools need -k / --tls-verify=false."
echo ""

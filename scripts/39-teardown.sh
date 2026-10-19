#!/usr/bin/env bash
# =============================================================================
# 39-teardown.sh — ACT 5 cleanup (everything created by steps 30–38)
#
# 0. Deletes the Argo CD objects of step 36 in openshift-gitops (Application,
#    AppProject, repository Secret, pipeline Role) — before the namespaces, so
#    Argo CD does not try to re-sync a namespace that is going away.
# 1. Deletes the pipeline/app namespaces (CICD_PROJECT, DEV_PROJECT): Tasks,
#    Pipelines, runs, their PVCs, the deployed app and the PAC Repository CR.
# 2. Removes the in-cluster GitLab: namespace, GitLab + PostgreSQL Deployments,
#    PVCs (repos, registry images, database), Routes, credentials Secret and
#    the anyuid SCC RoleBinding — all namespace-scoped, so deleting the
#    namespace removes them. Waits until it is fully gone so
#    30-gitlab-setup.sh can be re-run immediately.
# 3. Restores the TektonConfig affinity-assistant coschedule mode changed by
#    step 30 (only if step 30 changed it — original value kept in an
#    annotation).
# 4. Deletes the ACS image integration created by step 32 (ACS_REGISTRY_INTEGRATION)
#    via the Central API — needs the token in KEYS_FILE; the delegated-scanning
#    registry entry is kept (shared Central).
# 5. Removes the GitLab registry CA that step 30 added to
#    image.config.openshift.io/cluster additionalTrustedCA (only what step 30
#    added; openshift-apiserver restarts briefly).
# Safe to run multiple times (idempotent).
#
# Not touched: other cluster-wide settings (e.g. the default StorageClass) and
# the ACT 1–4 namespaces (use 99-teardown.sh for those).
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/demo-config.sh"

header "ACT 5 — Teardown (GitLab, pipelines, Pipelines prep)"

check_login

ACS_TOKEN="$(get_key "${ACS_TOKEN_KEY}")"
ACS_INTEG_ID=""
if [[ -n "${ACS_TOKEN}" && -n "${ACS_CENTRAL_URL}" ]]; then
  ACS_INTEG_ID="$(curl -sk -H "Authorization: Bearer ${ACS_TOKEN}" "${ACS_CENTRAL_URL}/v1/imageintegrations" 2>/dev/null \
    | jq -r --arg n "${ACS_REGISTRY_INTEGRATION}" '.integrations[]? | select(.name == $n) | .id' | head -1 || true)"
fi
ARGO_OBJS="$( { oc get applications.argoproj.io "${ARGO_APP}" -n "${ARGO_NAMESPACE}" -o name; \
  oc get appprojects.argoproj.io "${ARGO_PROJECT}" -n "${ARGO_NAMESPACE}" -o name; \
  oc get secret "${GITOPS_PROJECT}-repo" -n "${ARGO_NAMESPACE}" -o name; \
  oc get role,rolebinding ked-demo-pipeline-app-reader -n "${ARGO_NAMESPACE}" -o name; } 2>/dev/null || true)"
ACT5_PROJECTS=()
for ns in "${CICD_PROJECT}" "${DEV_PROJECT}"; do
  oc get project "${ns}" &>/dev/null && ACT5_PROJECTS+=("${ns}")
done
HAS_GITLAB=false
oc get project "${GITLAB_NAMESPACE}" &>/dev/null && HAS_GITLAB=true
ORIG_COSCHEDULE="$(oc get tektonconfig config -o json 2>/dev/null \
  | jq -r --arg a "${TEKTON_COSCHEDULE_ANNOTATION}" '.metadata.annotations[$a] // empty' || true)"
# Registry CA: either our own ConfigMap set by step 30 (annotation on
# image.config) or a key added to a pre-existing ConfigMap (annotation on it)
OWN_CA_CM="$(oc get image.config.openshift.io cluster -o json 2>/dev/null \
  | jq -r --arg a "${REGISTRY_CA_ANNOTATION}" '.metadata.annotations[$a] // empty' || true)"
SHARED_CA_CM="" SHARED_CA_KEY=""
if [[ -z "${OWN_CA_CM}" ]]; then
  SHARED_CA_CM="$(oc get image.config.openshift.io cluster -o jsonpath='{.spec.additionalTrustedCA.name}' 2>/dev/null || true)"
  [[ -n "${SHARED_CA_CM}" ]] && SHARED_CA_KEY="$(oc get cm "${SHARED_CA_CM}" -n openshift-config -o json 2>/dev/null \
    | jq -r --arg a "${REGISTRY_CA_ANNOTATION}-key" '.metadata.annotations[$a] // empty' || true)"
fi

if [[ -z "${ARGO_OBJS}" ]] && (( ${#ACT5_PROJECTS[@]} == 0 )) && [[ "${HAS_GITLAB}" == false && -z "${ORIG_COSCHEDULE}" \
      && -z "${OWN_CA_CM}" && -z "${SHARED_CA_KEY}" && -z "${ACS_INTEG_ID}" ]]; then
  ok "Nothing from ACT 5 found — nothing to clean up"
  exit 0
fi

step "What will be cleaned up:"
[[ -n "${ARGO_OBJS}" ]] && echo -e "  Argo CD (${ARGO_NAMESPACE}): ${CYAN}$(echo ${ARGO_OBJS} | tr '\n' ' ')${RESET}"
for ns in "${ACT5_PROJECTS[@]}"; do
  echo -e "  Project ${CYAN}${ns}${RESET} (pipelines, runs, PVCs, app)"
done
if [[ "${HAS_GITLAB}" == true ]]; then
  oc get deploy,svc,route,pvc -n "${GITLAB_NAMESPACE}" 2>/dev/null || true
  oc get secret "${GITLAB_CREDS_SECRET}" -n "${GITLAB_NAMESPACE}" 2>/dev/null || true
  warn "This DELETES GitLab in '${GITLAB_NAMESPACE}': all repos, registry images and credentials."
fi
if [[ -n "${ORIG_COSCHEDULE}" ]]; then
  echo -e "  TektonConfig coschedule: ${CYAN}$(oc get tektonconfig config -o jsonpath='{.spec.pipeline.coschedule}')${RESET} → restore to ${CYAN}${ORIG_COSCHEDULE}${RESET}"
fi
[[ -n "${ACS_INTEG_ID}" ]] && echo -e "  ACS image integration ${CYAN}${ACS_REGISTRY_INTEGRATION}${RESET} (${ACS_CENTRAL_URL})"
if [[ -n "${OWN_CA_CM}" ]]; then
  echo -e "  image.config additionalTrustedCA: remove ${CYAN}openshift-config/${OWN_CA_CM}${RESET} (GitLab registry CA)"
elif [[ -n "${SHARED_CA_KEY}" ]]; then
  echo -e "  image.config additionalTrustedCA: remove key ${CYAN}${SHARED_CA_KEY}${RESET} from ${CYAN}openshift-config/${SHARED_CA_CM}${RESET}"
fi
echo ""
echo -n "  Are you sure? (yes/no): "
read -r CONFIRM
if [[ "${CONFIRM}" != "yes" ]]; then
  echo "Aborted."
  exit 0
fi

# ── Argo CD objects (step 36) — first, so nothing re-syncs into dev ─────────
if [[ -n "${ARGO_OBJS}" ]]; then
  step "Deleting Argo CD objects in '${ARGO_NAMESPACE}'..."
  # shellcheck disable=SC2086
  oc delete ${ARGO_OBJS} -n "${ARGO_NAMESPACE}" --ignore-not-found >/dev/null
  ok "Application, AppProject, repository Secret and pipeline Role removed"
fi

# ── Delete the pipeline / app namespaces (steps 31+) ──────────────────────────
if (( ${#ACT5_PROJECTS[@]} > 0 )); then
  step "Deleting project(s) ${ACT5_PROJECTS[*]}..."
  for ns in "${ACT5_PROJECTS[@]}"; do
    oc delete project "${ns}" --wait=false 2>/dev/null || true
  done
  for ns in "${ACT5_PROJECTS[@]}"; do
    oc wait namespace/"${ns}" --for=delete --timeout=300s &>/dev/null \
      && ok "Project '${ns}' deleted" \
      || warn "Project '${ns}' still terminating — check: oc get ns ${ns}"
  done
fi

# ── ACS image integration (step 32) ──────────────────────────────────────────
if [[ -n "${ACS_INTEG_ID}" ]]; then
  step "Deleting ACS image integration '${ACS_REGISTRY_INTEGRATION}'..."
  curl -sk -X DELETE -H "Authorization: Bearer ${ACS_TOKEN}" \
    "${ACS_CENTRAL_URL}/v1/imageintegrations/${ACS_INTEG_ID}" >/dev/null
  ok "ACS image integration deleted"
fi

# ── Restore the Tekton affinity assistant mode (cluster-wide) ────────────────
if [[ -n "${ORIG_COSCHEDULE}" ]]; then
  step "Restoring TektonConfig coschedule='${ORIG_COSCHEDULE}'..."
  oc patch tektonconfig config --type merge \
    -p "{\"spec\":{\"pipeline\":{\"coschedule\":\"${ORIG_COSCHEDULE}\"}}}" >/dev/null
  oc annotate tektonconfig config "${TEKTON_COSCHEDULE_ANNOTATION}-" >/dev/null
  ok "TektonConfig coschedule restored"
fi

# ── Remove the GitLab registry CA from the node trust (cluster-wide) ─────────
if [[ -n "${OWN_CA_CM}" ]]; then
  step "Removing additionalTrustedCA '${OWN_CA_CM}' from image.config cluster..."
  oc patch image.config.openshift.io cluster --type json \
    -p '[{"op":"remove","path":"/spec/additionalTrustedCA"}]' >/dev/null 2>&1 || true
  oc annotate image.config.openshift.io cluster "${REGISTRY_CA_ANNOTATION}-" >/dev/null
  oc delete cm "${OWN_CA_CM}" -n openshift-config --ignore-not-found >/dev/null
  ok "Registry CA removed (openshift-apiserver restarts briefly)"
elif [[ -n "${SHARED_CA_KEY}" ]]; then
  step "Removing key '${SHARED_CA_KEY}' from ConfigMap openshift-config/${SHARED_CA_CM}..."
  oc patch cm "${SHARED_CA_CM}" -n openshift-config --type json \
    -p "$(jq -nc --arg k "${SHARED_CA_KEY}" '[{op: "remove", path: ("/data/" + $k)}]')" >/dev/null 2>&1 || true
  oc annotate cm "${SHARED_CA_CM}" -n openshift-config "${REGISTRY_CA_ANNOTATION}-key-" >/dev/null
  ok "Registry CA key removed"
fi

if [[ "${HAS_GITLAB}" == true ]]; then
  # ── Delete the GitLab namespace (everything else from step 30 lives in it) ─
  step "Deleting project '${GITLAB_NAMESPACE}'..."
  oc delete project "${GITLAB_NAMESPACE}" --wait=false 2>/dev/null || true

  step "Waiting for the namespace to be fully removed (PVCs/PVs released)..."
  if oc wait namespace/"${GITLAB_NAMESPACE}" --for=delete --timeout=600s &>/dev/null; then
    ok "Project '${GITLAB_NAMESPACE}' deleted"
  else
    warn "Namespace still terminating — check: oc get ns ${GITLAB_NAMESPACE} -o yaml"
    exit 1
  fi

  # ── Confirm no PersistentVolumes from the GitLab claims are left behind ────
  LEFT_PVS="$(oc get pv -o jsonpath='{range .items[?(@.spec.claimRef.namespace=="'"${GITLAB_NAMESPACE}"'")]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)"
  if [[ -n "${LEFT_PVS}" ]]; then
    warn "PersistentVolumes still bound to '${GITLAB_NAMESPACE}' claims (reclaim policy?):"
    echo "${LEFT_PVS}"
  else
    ok "No PersistentVolumes left behind"
  fi
fi

echo ""
echo -e "${GREEN}${BOLD}ACT 5 teardown complete.${RESET}"
echo -e "  Re-create with ${CYAN}./scripts/30-gitlab-setup.sh${RESET}"
echo ""

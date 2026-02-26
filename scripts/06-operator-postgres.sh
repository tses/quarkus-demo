#!/usr/bin/env bash
# =============================================================================
# 06-operator-postgres.sh — Deploy Postgres via OperatorHub (CLI helper)
# NOTE: The main demo for this section is done via the Console UI (OperatorHub)
#       This script provides CLI verification steps AFTER the operator is installed.
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/demo-config.sh"

header "ACT 3 — Postgres Operator (CLI verification)"

check_login
use_project

# ── Ensure the DB namespace exists ───────────────────────────────────────────
step "Ensuring database namespace '${DB_NAMESPACE}' exists..."
oc project "${DB_NAMESPACE}" &>/dev/null || \
  oc new-project "${DB_NAMESPACE}" --display-name="${DB_NAMESPACE_DISPLAY}"
ok "Using database namespace: ${DB_NAMESPACE}"
echo ""

echo -e "${YELLOW}  ℹ  Install the Postgres Operator via Console first:${RESET}"
echo -e "     Administrator → Operators → OperatorHub → search 'PostgreSQL'${RESET}"
echo -e "     Install 'Crunchy Postgres for Kubernetes' → then return here.${RESET}"
echo ""
pause

# ── Step 1: Verify operator is installed ─────────────────────────────────────
step "Checking installed operators..."
oc get csv -n "${DB_NAMESPACE}" 2>/dev/null | grep -i postgres || \
  oc get csv -A 2>/dev/null | grep -i postgres || \
  warn "No Postgres operator found — install from OperatorHub first"
echo ""
pause

# ── Step 2: Create a PostgresCluster CR ──────────────────────────────────────
step "Creating a PostgresCluster via YAML..."
show_cmd "apiVersion: postgres-operator.crunchydata.com/v1beta1
kind: PostgresCluster
metadata:
  name: ${DB_CLUSTER_NAME}
spec:
  postgresVersion: 16
  instances:
    - name: instance1
      replicas: 1
      dataVolumeClaimSpec:
        accessModes: [ReadWriteOnce]
        resources:
          requests:
            storage: 1Gi
  backups:
    pgbackrest:
      repos:
        - name: repo1
          volume:
            volumeClaimSpec:
              accessModes: [ReadWriteOnce]
              resources:
                requests:
                  storage: 1Gi"
# postgresVersion 16 — matches the image digest available in this cluster's
# operator CSV (postgresoperator.v5.8.6). PGO v5 requires an explicit image:
# when the version cannot be auto-resolved from the operator environment.
cat << EOF | oc apply -n "${DB_NAMESPACE}" -f -
apiVersion: postgres-operator.crunchydata.com/v1beta1
kind: PostgresCluster
metadata:
  name: ${DB_CLUSTER_NAME}
spec:
  postgresVersion: 16
  image: "registry.connect.redhat.com/crunchydata/crunchy-postgres@sha256:eced136169980e95d8f002e2f95cef44e4132a70d06e3399f236241d3899af76"
  instances:
    - name: instance1
      replicas: 1
      dataVolumeClaimSpec:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 1Gi
  backups:
    pgbackrest:
      repos:
        - name: repo1
          volume:
            volumeClaimSpec:
              accessModes:
                - ReadWriteOnce
              resources:
                requests:
                  storage: 1Gi
EOF
echo ""
ok "PostgresCluster '${DB_CLUSTER_NAME}' created in namespace '${DB_NAMESPACE}'"

# ── Step 3: Watch it come up ──────────────────────────────────────────────────
step "Watching Postgres pods appear in '${DB_NAMESPACE}' (this takes ~60s)..."
echo -e "${YELLOW}  Switch to Topology view to see pods appear visually${RESET}"
echo ""

for i in $(seq 1 12); do
  sleep 5
  PODS=$(oc get pods -n "${DB_NAMESPACE}" \
    -l "postgres-operator.crunchydata.com/cluster=${DB_CLUSTER_NAME}" \
    --no-headers 2>/dev/null || true)
  RUNNING=$(echo "${PODS}" | grep -c "Running" || true)
  TOTAL=$(echo "${PODS}" | grep -c "." || true)
  echo -e "  [t+$((i*5))s] Postgres pods: ${GREEN}${RUNNING}/${TOTAL} Running${RESET}"
  if [[ "${RUNNING}" -ge 1 ]]; then break; fi
done
echo ""

# ── Step 4: Show auto-created secrets ────────────────────────────────────────
step "Secrets auto-created by the Operator (namespace: ${DB_NAMESPACE}):"
oc get secrets -n "${DB_NAMESPACE}" | grep "${DB_CLUSTER_NAME}" || \
  echo "  (secrets not yet created — cluster may still be initializing)"
echo ""

# ── Step 5: Show connection string ───────────────────────────────────────────
step "Connection secret (your app uses this — no one hard-codes passwords):"
SECRET_NAME="${DB_CLUSTER_NAME}-pguser-${DB_CLUSTER_NAME}"
if oc get secret "${SECRET_NAME}" -n "${DB_NAMESPACE}" &>/dev/null; then
  oc get secret "${SECRET_NAME}" -n "${DB_NAMESPACE}" \
    -o jsonpath='{.data.uri}' | base64 -d
  echo ""
else
  warn "Secret not ready yet — Operator is still initializing the cluster"
fi
echo ""
ok "Postgres Operator demo complete."

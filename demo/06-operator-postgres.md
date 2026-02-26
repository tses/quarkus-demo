# ACT 3 — Deploying the Postgres Operator

> **Script:** `scripts/06-operator-postgres.sh` (CLI verification after console install)
> **Overview:** The Operator pattern enables provisioning of a production-grade PostgreSQL cluster via a custom resource, with no manual DBA steps.

---

## Mental Model

**What is an Operator?**

> An Operator is a Kubernetes controller that encodes **operational knowledge** — install, configure, backup, failover, upgrade — as automated reconciliation logic.

**Without an Operator:**
- Deploy a DB container manually
- Write and maintain backup scripts
- Handle failover and credential rotation manually
- Manage upgrades with risk of data loss

**With an Operator:**
- Declare the desired state in a Custom Resource (CR)
- The Operator reconciles actual state to match declared state — continuously

> **Key point:** An Operator replaces manual Day-2 operations. It is always available, always consistent, and does not require a support ticket.

---

## Steps

### 1. OperatorHub

**Operators → OperatorHub**

Search for: `PostgreSQL`

> **Note:** OperatorHub lists Red Hat certified, community, and ISV operators. The certification level indicates the level of support and testing.

Select **Crunchy Postgres for Kubernetes**.

---

### 2. Install the Operator

**Install** → review settings:

| Setting | Value |
|---|---|
| Installation Mode | Specific namespace (`ocp-demo`) |
| Update Channel | stable |
| Approval Strategy | Automatic |

---

### 3. Verify Operator Installation

```bash
oc get csv -n ocp-demo | grep -i postgres
```

Wait for `PHASE: Succeeded` before proceeding.

---

### 4. PostgresCluster Custom Resource

```yaml
apiVersion: postgres-operator.crunchydata.com/v1beta1
kind: PostgresCluster
metadata:
  name: demo-db
spec:
  postgresVersion: 16
  image: "registry.connect.redhat.com/crunchydata/crunchy-postgres@sha256:eced136..."
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
                  storage: 1Gi
```

> **Key point:** This YAML expresses *what* is needed. The Operator determines *how* to provision it — pods, PVCs, services, secrets — and maintains that state going forward.

---

### 5. Cluster Provisioning

Postgres pods appear in **Topology** within ~60 seconds.

```bash
oc get pods -l postgres-operator.crunchydata.com/cluster=demo-db -n ocp-demo
```

> **Note:** The Operator creates: the Postgres pod, a pgBackRest sidecar for backups, and a Kubernetes `Secret` containing connection credentials — all from the single CR above.

---

### 6. Connection Secret

```bash
oc get secret demo-db-pguser-demo-db -n ocp-demo \
  -o jsonpath='{.data.uri}' | base64 -d
```

> **Key point:** Applications consume this secret as an environment variable. No developer or operator sees the credentials directly — the Operator generates and rotates them.

---

## Recap

| Without Operator | With Operator |
|---|---|
| Manual installation and configuration | Installed via OperatorHub in 2 clicks |
| Custom backup scripts | Built-in pgBackRest integration |
| Manual failover procedures | Automated reconciliation |
| Manual credential management | Operator-managed secrets |
| Upgrades are high-risk, manual | Controlled rolling upgrades |

---

## ⬅️ Previous: [Traffic Splitting](05-traffic-splitting.md) | ➡️ Next: [Health Probes](07-probes.md)

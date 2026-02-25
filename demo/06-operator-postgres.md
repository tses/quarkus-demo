# ACT 3 — Deploying the Postgres Operator

> **Duration:** ~8 minutes  
> **Script:** `scripts/06-operator-postgres.sh` (CLI verification after console install)  
> **Wow Factor:** Production-grade database in 2 clicks — no DBA, no ticket, no waiting  
> **Message:** *"Operators φέρνουν Day-2 operations μέσα στο platform."*

---

## 🎯 Mental Model First

**What is an Operator?**

> An Operator is a Kubernetes controller that encodes **human operational knowledge** into software.

> 💬 *"Φανταστείτε έναν έμπειρο DBA που ξέρει πώς να στήσει Postgres, να κάνει backup, failover, και upgrade — και τον 'έχετε' πάντα available, 24/7, automated. Αυτός είναι ο Operator."*

**Without Operator:** Deploy DB container → configure manually → write backup scripts → handle failover manually.  
**With Operator:** Define what you want → Operator handles everything else.

---

## 🖥️ Steps

### 1. Navigate to OperatorHub (Console)

Navigate to: **Administrator → Operators → OperatorHub**

Search for: `PostgreSQL`

> 💬 *"Το OperatorHub είναι marketplace από certified operators. Red Hat, community, ISVs."*

Select **Crunchy Postgres for Kubernetes**.

---

### 2. Install the Operator

Click **Install** → review settings:
- **Installation Mode:** A specific namespace (`ocp-demo`)
- **Update Channel:** stable
- **Approval Strategy:** Automatic

Click **Install** again. Then return to the terminal.

---

### 3. Verify operator is installed

```bash
oc get csv -n ocp-demo | grep -i postgres
```

---

### 4. Create a PostgresCluster CR

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

> 💬 *"Αυτό το YAML είναι η 'επιθυμία' μας. Ο Operator κάνει τα υπόλοιπα — pods, secrets, services, storage."*

---

### 5. Watch it come up

Navigate to: **Developer → Topology** — Postgres pods appear (~60s)

```bash
oc get pods -l postgres-operator.crunchydata.com/cluster=demo-db -n ocp-demo
```

> 💬 *"Ο Operator έφτιαξε: postgres pod, backup sidecar, secrets με credentials. Αυτόματα."*

---

### 6. Show the connection secret

```bash
oc get secret demo-db-pguser-demo-db -n ocp-demo \
  -o jsonpath='{.data.uri}' | base64 -d
```

> 💬 *"Η εφαρμογή μας μπορεί να χρησιμοποιήσει αυτό το secret. Το password δεν το ξέρει κανείς — διαχειρίζεται ο Operator."*

---

## 📌 Recap

| Χωρίς Operator | Με Operator |
|----------------|-------------|
| Manual install & config | 2 clicks |
| Custom backup scripts | Built-in |
| Manual failover | Automated |
| You manage credentials | Operator manages secrets |
| Upgrades = risk | Controlled rolling upgrades |

---

## ➡️ Next: [Monitoring](07-monitoring.md)

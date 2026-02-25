# ACT 3 — Deploying the Postgres Operator

> **Duration:** ~8 minutes  
> **Wow Factor:** Production-grade database in 2 clicks — no DBA, no ticket, no waiting  
> **Message:** *"Operators φέρνουν Day-2 operations μέσα στο platform."*

---

## 🎯 Mental Model First

**What is an Operator?**

> An Operator is a Kubernetes controller that encodes **human operational knowledge** into software.

Αναλογία:
> 💬 *"Φανταστείτε έναν έμπειρο DBA που ξέρει πώς να στήσει Postgres, να κάνει backup, failover, και upgrade — και τον 'έχετε' πάντα available, 24/7, automated. Αυτός είναι ο Operator."*

**Without Operator:** Deploy DB container → configure manually → write backup scripts → handle failover manually.  
**With Operator:** Define what you want → Operator handles everything else.

---

## 🖥️ Steps

### 1. Navigate to OperatorHub

Navigate to: **Administrator → Operators → OperatorHub**

Search for: `PostgreSQL`

> 💬 *"Το OperatorHub είναι marketplace από certified operators. Red Hat, community, ISVs."*

Show the options:
- **Crunchy Postgres for Kubernetes** (production-grade)
- **CloudNativePG** (community favorite)

Select **Crunchy Postgres for Kubernetes** (or whichever is available on your cluster).

---

### 2. Install the Operator

Click **Install** → review settings:
- **Installation Mode:** A specific namespace (our demo project)
- **Update Channel:** stable
- **Approval Strategy:** Automatic

Click **Install** again.

> 💬 *"Η εγκατάσταση γίνεται στο επίπεδο του cluster. Μόλις εγκατασταθεί, ο Operator 'βλέπει' το namespace μας."*

---

### 3. Create a PostgresCluster instance

Navigate to: **Operators → Installed Operators → Crunchy Postgres → Create Instance**

Use the **Form view** (not YAML) to show the simplicity:
- Cluster name: `demo-db`
- PostgreSQL version: `14`
- Number of instances: `1`
- Storage size: `1Gi`

Click **Create**.

```yaml
# What gets created under the hood:
apiVersion: postgres-operator.crunchydata.com/v1beta1
kind: PostgresCluster
metadata:
  name: demo-db
spec:
  postgresVersion: 14
  instances:
    - replicas: 1
      dataVolumeClaimSpec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 1Gi
```

> 💬 *"Αυτό το YAML είναι η 'επιθυμία' μας. Ο Operator κάνει τα υπόλοιπα — pods, secrets, services, storage."*

---

### 4. Watch it come up

Navigate to: **Developer → Topology** — Postgres pods appear

```bash
oc get pods -l postgres-operator.crunchydata.com/cluster=demo-db
oc get secrets | grep demo-db
```

> 💬 *"Ο Operator έφτιαξε: postgres pod, backup sidecar, monitoring sidecar, secrets με credentials. Αυτόματα."*

---

### 5. Show the connection secret

```bash
oc get secret demo-db-pguser-demo-db -o jsonpath='{.data.uri}' | base64 -d
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

## ➡️ Next: [Monitoring with Grafana](../07-monitoring/README.md)

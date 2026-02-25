# ACT 3 — Traffic Splitting

> **Duration:** ~8 minutes  
> **Script:** `scripts/05-traffic-splitting.sh`  
> **Wow Factor:** Canary release με live traffic weights — audience sees both versions respond  
> **Message:** *"Production risk management με μία εντολή. Zero downtime. Zero on-call panic."*

---

## 🎯 Mental Model First

> 💬 *"Φανταστείτε ότι βγάλατε νέα έκδοση. Δεν είστε 100% σίγουροι ότι είναι OK. Τι κάνετε;"*

**Old world:** Deploy to staging → wait → deploy to prod → pray.  
**OpenShift:** Send 10% of REAL traffic to v2. Watch metrics. If OK → slide to 100%. If not → slide back to 0.

This is **Canary Deployment**. No extra infrastructure. Built in.

---

## 🖥️ Steps

### 1. Deploy v2 (same source, different env labels)

```bash
oc new-app \
  -i openshift/java:openjdk-17-ubi8 \
  --code=https://github.com/tses/quarkus-demo \
  --context-dir=app/ocp-demo-app \
  --name=ocp-demo-app-v2 \
  --labels=app=ocp-demo-app-v2,demo=ocp-intro,version=v2 \
  -n ocp-demo

# Mark v2 visually — /api/info returns "colour":"green"
oc set env deployment/ocp-demo-app-v2 \
  APP_COLOUR=green APP_VERSION=2.0.0 -n ocp-demo
```

> 💬 *"Έχουμε δύο εκδόσεις. Η v1 παίρνει όλο το traffic τώρα. Θα αλλάξουμε αυτό."*

Both deployments visible as separate nodes in **Developer → Topology**.

---

### 2. Split 90% v1 / 10% v2

```bash
oc patch route ocp-demo-app -n ocp-demo --type=merge -p '{
  "spec": {
    "to": {"kind":"Service","name":"ocp-demo-app","weight":90},
    "alternateBackends": [{"kind":"Service","name":"ocp-demo-app-v2","weight":10}]
  }
}'
```

The script then sends **20 requests** and prints which version responded:

```
Request 1:  {"colour":"blue",...}   ← v1
Request 5:  {"colour":"green",...}  ← v2  ← highlighted in yellow
...
v1 responses: 18/20  |  v2 responses: 2/20
```

> 💬 *"Βλέπετε; Κάποια requests πάνε στη v1, κάποια στη v2. 90/10 split."*

---

### 3. Move to 50/50

```bash
oc patch route ocp-demo-app -n ocp-demo --type=merge -p '{
  "spec": {
    "to": {"kind":"Service","name":"ocp-demo-app","weight":50},
    "alternateBackends": [{"kind":"Service","name":"ocp-demo-app-v2","weight":50}]
  }
}'
```

> 💬 *"Τώρα 50/50. Παρακολουθούμε metrics. Αν η v2 είναι OK — πάμε 100%."*

---

### 4. Full cutover to v2

```bash
oc patch route ocp-demo-app -n ocp-demo --type=merge -p '{
  "spec": {
    "to": {"kind":"Service","name":"ocp-demo-app-v2","weight":100},
    "alternateBackends": []
  }
}'
```

> 💬 *"Μετακίνηση ολοκληρώθηκε. Κανένας χρήστης δεν είδε error."*

---

### 5. Emergency rollback (back to v1)

```bash
oc patch route ocp-demo-app -n ocp-demo --type=merge -p '{
  "spec": {
    "to": {"kind":"Service","name":"ocp-demo-app","weight":100},
    "alternateBackends": []
  }
}'
```

> 💬 *"Rollback: ένα command. Τέλος."*

---

### 6. Cleanup — v2 removed automatically

At the end of the script, v2 resources are deleted so they don't interfere with later demos:

```bash
oc delete deployment,svc,bc,is ocp-demo-app-v2 -n ocp-demo --ignore-not-found
```

---

## 📌 Recap

| Action | Time | Risk |
|--------|------|------|
| Deploy v2 silently | seconds | Zero |
| Send 10% traffic | 1 command | Minimal |
| Monitor & grow to 100% | gradual | Controlled |
| Emergency rollback | 1 command | Instant |

---

## ➡️ Next: [Deploy Postgres Operator](06-operator-postgres.md)

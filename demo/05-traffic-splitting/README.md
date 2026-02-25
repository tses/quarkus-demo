# ACT 3 — Traffic Splitting ⭐ WOW #2

> **Duration:** ~8 minutes  
> **Wow Factor:** Canary release με visual weight slider — live, in front of the audience  
> **Message:** *"Production risk management με drag-and-drop. Zero downtime. Zero on-call panic."*

---

## 🎯 Mental Model First

> 💬 *"Φανταστείτε ότι βγάλατε νέα έκδοση. Δεν είστε 100% σίγουροι ότι είναι OK. Τι κάνετε;"*

**Old world:** Deploy to staging → wait → deploy to prod → pray.  
**OpenShift:** Send 10% of REAL traffic to v2. Watch metrics. If OK → slide to 100%. If not → slide back to 0.

This is **Canary Deployment**. No extra infrastructure. Built in.

---

## 🛠️ Pre-Demo Setup

You need **two deployments** ready before this demo step:

```bash
# v1 is already running (from S2I demo)
# Deploy v2 (different image tag or branch)
oc new-app <your-repo>#v2 --name=my-app-v2

# Scale v2 to 1 replica (it will receive traffic based on weight, not replicas)
oc scale deployment/my-app-v2 --replicas=1
```

> ⚠️ **Important:** Both deployments must be in the same project and have Routes.

---

## 🖥️ Steps

### 1. Show both deployments in Topology

Navigate to: **Developer → Topology**

Both `my-app` (v1) and `my-app-v2` should be visible as separate nodes.

> 💬 *"Έχουμε δύο εκδόσεις. Η v1 παίρνει όλο το traffic τώρα. Θα αλλάξουμε αυτό."*

---

### 2. Open the Route for Traffic Splitting

Navigate to: **Developer → Project → Routes**  
Click on the route for `my-app` → **Actions → Edit Route**

Or navigate via: **Networking → Routes → my-app → YAML**

Switch to the **Traffic tab** if available in your OCP version, or edit the Route YAML:

```yaml
spec:
  to:
    kind: Service
    name: my-app
    weight: 90
  alternateBackends:
    - kind: Service
      name: my-app-v2
      weight: 10
```

> 💬 *"Αυτό ορίζει: 90% του traffic πάει στη v1, 10% στη v2. Ας το ενεργοποιήσουμε."*

---

### 3. Apply and verify live

```bash
# Apply via CLI
oc patch route my-app -p '{
  "spec": {
    "to": {"kind":"Service","name":"my-app","weight":90},
    "alternateBackends": [{"kind":"Service","name":"my-app-v2","weight":10}]
  }
}'

# Verify in a loop — watch which version responds
for i in $(seq 1 20); do
  curl -s https://$(oc get route my-app -o jsonpath='{.spec.host}')/version
  echo ""
done
```

> 💬 *"Βλέπετε; Κάποια requests πάνε στη v1, κάποια στη v2. 90/10 split — exactly."*

---

### 4. The "Slider" Moment — Move to 50/50

Update weights to 50/50:

```bash
oc patch route my-app -p '{
  "spec": {
    "to": {"kind":"Service","name":"my-app","weight":50},
    "alternateBackends": [{"kind":"Service","name":"my-app-v2","weight":50}]
  }
}'
```

> 💬 *"Τώρα 50/50. Παρακολουθούμε metrics. Αν η v2 είναι OK — πάμε 100%."*

---

### 5. Full cutover to v2

```bash
oc patch route my-app -p '{
  "spec": {
    "to": {"kind":"Service","name":"my-app-v2","weight":100},
    "alternateBackends": []
  }
}'
```

> 💬 *"Μετακίνηση ολοκληρώθηκε. Κανένας χρήστης δεν είδε error. Κανένας engineer δεν ξύπνησε στις 3 το βράδυ."*

---

### 6. (Optional) Emergency rollback

```bash
# Back to v1 instantly
oc patch route my-app -p '{
  "spec": {
    "to": {"kind":"Service","name":"my-app","weight":100},
    "alternateBackends": []
  }
}'
```

> 💬 *"Rollback: ένα command. Τέλος."*

---

## 📌 Recap

| Action | Time | Risk |
|--------|------|------|
| Deploy v2 silently | seconds | Zero |
| Send 10% traffic | 1 command | Minimal |
| Monitor & grow to 100% | gradual | Controlled |
| Emergency rollback | 1 command | Instant |

---

## ➡️ Next: [Deploy Postgres Operator](../06-operator-postgres/README.md)

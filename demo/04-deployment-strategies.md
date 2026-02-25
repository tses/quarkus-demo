# ACT 3 — Deployment Strategies

> **Duration:** ~8 minutes  
> **Script:** `scripts/04-deployment-strategies.sh`  
> **Wow Factor:** Visual rolling update — pods cycling live in Topology view  
> **Message:** *"Zero downtime deployment — ενσωματωμένο, όχι custom script."*

---

## 🎯 Mental Model First

Two strategies, one critical difference:

```
RollingUpdate  → new pods UP before old pods DOWN  (zero downtime)
Recreate       → all old pods DOWN, then new pods UP (brief downtime, needed for DB migrations)
```

> 💬 *"Η ερώτηση δεν είναι 'ποιο είναι καλύτερο'. Είναι 'τι χρειάζεται η εφαρμογή σας'."*

---

## 🖥️ Steps

### 1. Show current strategy & explain the parameters

The script prints an explanation **before** showing the live values:

```
maxSurge: 25%       — how many EXTRA pods can run above the desired count during the update
                      (e.g. 4 replicas → up to 5 pods running at once)
maxUnavailable: 25% — how many pods can be unavailable at the same time
                      (e.g. 4 replicas → at least 3 always serving traffic)
```

> 💬 *"maxSurge και maxUnavailable μαζί εγγυώνται zero downtime: τα νέα pods ανεβαίνουν ΠΡΙΝ τα παλιά κατεβούν."*

Then the live deployment config:

```bash
oc get deployment ocp-demo-app -n ocp-demo \
  -o jsonpath='Strategy: {.spec.strategy.type}
MaxSurge: {.spec.strategy.rollingUpdate.maxSurge}
MaxUnavailable: {.spec.strategy.rollingUpdate.maxUnavailable}'
```

---

### 2. Trigger a rollout — watch it live

```bash
# Inject APP_VERSION env var — MicroProfile maps app.version → APP_VERSION
# /api/info will return the new version value after rollout
oc set env deployment/ocp-demo-app APP_VERSION=v<timestamp> -n ocp-demo

# Annotate so rollout history shows a meaningful CHANGE-CAUSE
oc annotate deployment/ocp-demo-app \
  kubernetes.io/change-cause="demo rollout v<timestamp>" --overwrite -n ocp-demo
```

Switch to **Topology view** — watch pods cycling (old terminating, new starting).

> 💬 *"Βλέπετε τι συμβαίνει; Τα παλιά pods δεν σταματάνε μέχρι τα νέα να είναι healthy. Η εφαρμογή ήταν πάντα available."*

After the rollout, `curl /api/info` returns the updated `"version"` value — proving it works.

---

### 3. Show Rollout History with CHANGE-CAUSE

```bash
oc rollout history deployment/ocp-demo-app -n ocp-demo
```

Each revision now shows a meaningful `CHANGE-CAUSE` annotation.

> 💬 *"Κάθε deployment καταγράφεται. Μπορούμε να πάμε πίσω σε οποιοδήποτε σημείο."*

---

### 4. Rollback in one command

```bash
oc rollout undo deployment/ocp-demo-app -n ocp-demo
```

> 💬 *"Ένα command. Production rollback. Χωρίς panic, χωρίς hotfix."*

---

### 5. Show Recreate strategy (explain only)

```yaml
strategy:
  type: Recreate          # ALL old pods stop first → THEN new pods start
                          # Use when 2 versions CANNOT run simultaneously
                          # (e.g. DB schema migration)
```

> 💬 *"Το Recreate χρησιμοποιείται όταν η εφαρμογή δεν μπορεί να τρέξει δύο εκδόσεις ταυτόχρονα. Ο χρόνος downtime είναι ελεγχόμενος και αναμενόμενος."*

---

## 📌 Recap

| Strategy | Downtime | Use When |
|----------|----------|----------|
| `RollingUpdate` | Zero | Stateless apps, APIs |
| `Recreate` | Brief, controlled | DB migrations, singleton apps |
| Rollback | Instant | Something went wrong |

---

## ➡️ Next: [Traffic Splitting](05-traffic-splitting.md)

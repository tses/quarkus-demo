# ACT 3 — Scaling Out

> **Duration:** ~5 minutes  
> **Script:** `scripts/08-scaling.sh`  
> **Wow Factor:** Manual scale in seconds + HPA auto-scale under real CPU load  
> **Message:** *"Scale up με ένα command ή αυτόματα — το platform αποφασίζει για σας."*

---

## 🎯 Mental Model First

Two types of scaling:

```
Manual Scaling  → εσύ αποφασίζεις πότε και πόσο
Auto Scaling    → το platform αποφασίζει βάσει metrics (HPA)
```

> 💬 *"Το manual scaling είναι για όταν ξέρεις ότι έρχεται load — π.χ. Black Friday. Το auto scaling είναι για όταν δεν ξέρεις."*

---

## 🖥️ Steps

### 1. Manual Scale UP to 3

```bash
oc scale deployment/ocp-demo-app --replicas=3 -n ocp-demo
```

Watch in Topology: 3 pods appear, all with dark blue ring.

The script also makes **6 requests** and shows the different `hostname` values in each response — proving load-balancing across all 3 pods.

> 💬 *"Τρία pods σε δευτερόλεπτα. Κάθε request πάει σε άλλο pod — το hostname αλλάζει."*

---

### 2. Scale back DOWN to 1

```bash
oc scale deployment/ocp-demo-app --replicas=1 -n ocp-demo
```

---

### 3. Horizontal Pod Autoscaler (HPA)

```bash
oc autoscale deployment/ocp-demo-app \
  --min=1 --max=5 --cpu-percent=50 \
  -n ocp-demo
```

```bash
oc get hpa ocp-demo-app -n ocp-demo
# NAME           TARGETS    MINPODS   MAXPODS   REPLICAS
# ocp-demo-app   <unknown>  1         5         1
```

> 💬 *"Αν το CPU ανέβει πάνω από 50%, το OpenShift ανεβάζει αυτόματα pods — μέχρι 5. Αν κατέβει — τα αφαιρεί."*

---

### 4. Trigger real CPU load — watch HPA react

The script launches **10 parallel clients**, each calling `/api/burn?seconds=90` for 120 seconds total:

```bash
# 10 background workers — each loops until 120s elapsed
for c in $(seq 1 10); do
  ( while true; do curl /api/burn?seconds=90 ...; sleep 1; done ) &
done
```

Every 5 seconds the script prints live pod status:

```
[t+0s]   ocp-demo-app-xxx(Running)
[t+30s]  ocp-demo-app-xxx(Running) ocp-demo-app-yyy(Running) ocp-demo-app-zzz(Running)
[t+60s]  ... 4 pods running
```

> 💬 *"Βλέπετε το HPA να αντιδρά. Χωρίς κανέναν να κάνει τίποτα."*

---

### 5. Cleanup — HPA removed, reset to 3 replicas

At the end of the script, the HPA is deleted and the deployment is reset to 3 replicas for the next demo (self-healing):

```bash
oc delete hpa ocp-demo-app -n ocp-demo --ignore-not-found
oc scale deployment/ocp-demo-app --replicas=3 -n ocp-demo
```

---

## 📌 Recap

| Method | When | Command |
|--------|------|---------|
| Manual scale | Known load event | `oc scale --replicas=N` |
| HPA | Unknown/variable load | `oc autoscale` |
| Scale to zero | Cost optimization (dev envs) | `oc scale --replicas=0` |

> 💬 *"Scale to zero είναι δυνατό επίσης — για dev environments που δεν χρειάζεστε τη νύχτα. Πλήρωνε για resources μόνο όταν χρειάζεσαι."*

---

## ➡️ Next: [Self-Healing Pods](09-self-healing.md)

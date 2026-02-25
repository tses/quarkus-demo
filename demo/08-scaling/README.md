# ACT 3 — Scaling Out

> **Duration:** ~5 minutes  
> **Wow Factor:** Manual scale in seconds + HPA auto-scale under load  
> **Message:** *"Scale up με ένα click ή αυτόματα — το platform αποφασίζει για σας."*

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

### 1. Manual Scale — Console

Navigate to: **Developer → Topology → App Node**

Click the **▲ (up arrow)** next to the pod count, or:

In the side panel → **Details** tab → pod count field → change `1` to `3`

> 💬 *"Τρία pods σε δευτερόλεπτα. Το traffic κατανέμεται αυτόματα."*

Watch in Topology: 3 pods appear, all with dark blue ring.

---

### 2. Manual Scale — CLI

```bash
oc scale deployment/my-app --replicas=3
oc get pods -l app=my-app -w   # watch pods appear
```

```bash
# Scale down just as easily
oc scale deployment/my-app --replicas=1
```

> 💬 *"Scale up, scale down — one command. Imagine doing this with VMs."*

---

### 3. Horizontal Pod Autoscaler (HPA)

Set up auto-scaling based on CPU:

```bash
oc autoscale deployment/my-app \
  --min=1 \
  --max=5 \
  --cpu-percent=70
```

Or via Console: **Developer → Topology → App Node → Actions → Add HPA**

```yaml
# What gets created:
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: my-app
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-app
  minReplicas: 1
  maxReplicas: 5
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

> 💬 *"Αν το CPU ανέβει πάνω από 70%, το OpenShift ανεβάζει αυτόματα pods — μέχρι 5. Αν κατέβει — τα αφαιρεί. Χωρίς intervention."*

---

### 4. Show HPA status

```bash
oc get hpa my-app
# NAME      REFERENCE            TARGETS   MINPODS   MAXPODS   REPLICAS
# my-app    Deployment/my-app    12%/70%   1         5         1
```

Navigate to: **Developer → Observe → Dashboard** — show CPU trend

---

## 📌 Recap

| Method | When | Command |
|--------|------|---------|
| Manual scale | Known load event | `oc scale --replicas=N` |
| HPA | Unknown/variable load | `oc autoscale` |
| Scale to zero | Cost optimization (dev envs) | `oc scale --replicas=0` |

> 💬 *"Scale to zero είναι δυνατό επίσης — για dev environments που δεν χρειάζεστε τη νύχτα. Πλήρωνε για resources μόνο όταν χρειάζεσαι."*

---

## ➡️ Next: [Self-Healing Pods](../09-self-healing/README.md) ⭐ WOW #3

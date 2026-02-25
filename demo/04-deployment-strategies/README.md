# ACT 3 — Deployment Strategies

> **Duration:** ~8 minutes  
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

### 1. Trigger a new Deployment (to show rolling update)

First, change the deployment strategy so the audience can see it:

Navigate to: **Developer → Topology → App Node → Actions → Edit Deployment**

Or via CLI:
```bash
oc edit deployment my-app
# Find strategy section — show current RollingUpdate config
```

Point out the `strategy` block:
```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 25%
    maxUnavailable: 25%
```

> 💬 *"maxSurge: μπορεί να έχει 25% παραπάνω pods κατά το update. maxUnavailable: ποτέ λιγότερο από 75% available. Αυτό εξασφαλίζει zero downtime."*

---

### 2. Trigger a rollout — watch it live

```bash
# Force a new rollout (simulates a new image being pushed)
oc rollout restart deployment/my-app
```

Switch to **Topology view** — watch pods cycling (old terminating, new starting).

> 💬 *"Βλέπετε τι συμβαίνει; Τα παλιά pods δεν σταματάνε μέχρι τα νέα να είναι healthy. Η εφαρμογή ήταν πάντα available."*

---

### 3. Show Rollout History

```bash
oc rollout history deployment/my-app
```

> 💬 *"Κάθε deployment καταγράφεται. Μπορούμε να πάμε πίσω σε οποιοδήποτε σημείο."*

---

### 4. Rollback in one command

```bash
oc rollout undo deployment/my-app
```

> 💬 *"Ένα command. Production rollback. Χωρίς panic, χωρίς hotfix."*

---

### 5. Show Recreate strategy (explain, don't necessarily demo)

```yaml
strategy:
  type: Recreate
```

> 💬 *"Το Recreate χρησιμοποιείται όταν η εφαρμογή δεν μπορεί να τρέξει δύο εκδόσεις ταυτόχρονα — π.χ. database schema migration. Ο χρόνος downtime είναι ελεγχόμενος και αναμενόμενος."*

---

## 📌 Recap

| Strategy | Downtime | Use When |
|----------|----------|----------|
| `RollingUpdate` | Zero | Stateless apps, APIs |
| `Recreate` | Brief, controlled | DB migrations, singleton apps |
| Rollback | Instant | Something went wrong |

---

## ➡️ Next: [Traffic Splitting](../05-traffic-splitting/README.md)

# ACT 2 — Pods / Service / Route

> **Duration:** ~10 minutes  
> **Wow Factor:** Visual topology — living architecture diagram, auto-updated  
> **Message:** *"Το OpenShift δεν κρύβει την πολυπλοκότητα — την οργανώνει."*

---

## 🎯 The Three Primitives

Before showing the UI, give a **30-second mental model**:

```
Pod          → the running process (your app, in a container)
Service      → stable internal address for a group of pods
Route        → public URL that points to the Service
```

> 💬 *"Φανταστείτε το σαν εστιατόριο: το Pod είναι ο σεφ, το Service είναι το ταμείο, το Route είναι η πόρτα που βλέπει ο κόσμος."*

---

## 🖥️ Steps

### 1. Topology View — The Living Diagram

Navigate to: **Developer → Topology**

Point out:
- The app node (circle) — tap it to expand
- The **dark blue ring** = pod is running and healthy
- The **arrow icon** (top-right of node) = Route URL

> 💬 *"Αυτό δεν είναι static diagram. Αλλάζει real-time καθώς τα pods ανεβοκατεβαίνουν."*

---

### 2. Click the App Node → Side Panel

Show the side panel tabs:
- **Details** — replicas, labels, image
- **Resources** — pods list, services, routes
- **Observe** — mini metrics inline

Click on the **Pod name** in Resources tab.

---

### 3. Inside the Pod

Navigate to: Pod detail page

Show tabs:
- **Details** — node it runs on, status, IP
- **Logs** — live application logs
- **Terminal** — shell INTO the running container

```bash
# Click "Terminal" tab — open a shell in the pod
ls /deployments
cat /etc/os-release
```

> 💬 *"Μπορούμε να μπούμε μέσα σε ένα running container από το browser. Χωρίς SSH. Χωρίς VPN. Για debug — αυτό είναι χρυσός."*

---

### 4. Show the Service

Navigate to: **Developer → Project → Services** (or from Resources tab)

```bash
# CLI equivalent
oc get svc
oc describe svc my-app
```

Point out:
- ClusterIP (internal only)
- Port mapping
- Selector (how it finds its pods)

> 💬 *"Το Service δεν ξέρει τίποτα για pods. Απλώς ρωτά: 'ποιος έχει αυτό το label;' Εκεί στέλνει traffic."*

---

### 5. Show the Route

Navigate to: **Networking → Routes**

```bash
# CLI equivalent
oc get route my-app
oc describe route my-app
```

Point out:
- **TLS termination** — HTTPS out of the box ✅
- The host URL pattern: `<app>-<project>.<cluster-domain>`

> 💬 *"HTTPS certificate — αυτόματο. Δεν χρειάστηκε να ρυθμίσει κανείς τίποτα."*

---

## 📌 Recap

| Concept | Αναλογία | Key insight |
|---------|----------|-------------|
| Pod | Ο σεφ | Εφήμερο — can die & be replaced |
| Service | Το ταμείο | Stable — always findable |
| Route | Η πόρτα | Public — HTTPS automatic |

---

## ➡️ Next: [Deployment Strategies](04-deployment-strategies.md)

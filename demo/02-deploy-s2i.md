# ACT 2 — Deploy with S2I

> **Duration:** ~10 minutes  
> **Message:** *"Ο developer δίνει κώδικα. Το platform κάνει τα υπόλοιπα."*

---

## 🎯 What is S2I?

**Source-to-Image (S2I)** is an OpenShift mechanism that:
1. Takes your **source code** (Git URL)
2. Detects the **language/framework** automatically
3. Builds a **container image** — no Dockerfile needed
4. **Deploys** it and exposes it — with a live URL

> 💬 *"Δεν χρειάζεστε να ξέρετε τίποτα για containers για να κάνετε deploy. Το platform το αφαιρεί."*

---

## 🖥️ Steps

### 1. Switch to Developer Perspective → +Add

Navigate to: **Developer → +Add → Import from Git**

---

### 2. Paste the Git URL

```
https://github.com/tses/quarkus-demo
```

Sub-directory (context dir): `app/ocp-demo-app`

> 💬 *"Αυτό είναι το repo μας. Quarkus Java application. Ας δούμε τι καταλαβαίνει το OpenShift..."*

**Pause** — let the console validate and auto-detect the builder image.

> 💬 *"Το είδε. Java 17. Διάλεξε μόνο του το κατάλληλο builder image."*

---

### 3. Review the auto-populated fields

Show the audience:
- **Builder Image**: `java:openjdk-17-ubi8` (auto-detected)
- **Application Name**: `ocp-demo-app`
- **Resource type**: Deployment (default)
- **Create a Route**: ✅ checked

> 💬 *"Θα μπορούσαμε να αλλάξουμε οτιδήποτε. Αλλά δεν χρειάζεται. Πατάμε Create."*

---

### 4. Click **Create** — and watch the build

Navigate to: **Developer → Topology** — the app appears with a spinner (building)

Click on the app node → **View Logs** (Build tab)

> 💬 *"Αυτό που βλέπετε είναι ο S2I builder να κατεβάζει dependencies, να κάνει compile, να φτιάχνει το container image. Real time."*

**⏳ Let the build stream. Do not skip this moment. The audience needs to see the logs moving.**

---

### 5. Build completes → Pod starts → Route is live

Back in Topology view:
- Build pod disappears
- App pod appears (dark blue ring = running)
- Route URL appears (top-right arrow icon)

Click the **Route URL** → app opens in browser at `/api/info`.

> 💬 *"Αυτό είναι production-ready URL. HTTPS. Load balanced. Από ένα Git URL, σε λίγα λεπτά."*

---

## ⚡ The CLI Equivalent (script: `scripts/02-deploy-s2i.sh`)

```bash
oc new-app \
  -i openshift/java:openjdk-17-ubi8 \
  --code=https://github.com/tses/quarkus-demo \
  --context-dir=app/ocp-demo-app \
  --name=ocp-demo-app \
  --labels=app=ocp-demo-app,demo=ocp-intro \
  -n ocp-demo

oc logs -f bc/ocp-demo-app -n ocp-demo

oc expose svc/ocp-demo-app -n ocp-demo
```

> 💬 *"Ακριβώς το ίδιο — τρεις εντολές. CI/CD pipeline το κάνει αυτό αυτόματα."*

---

## 🔗 App Endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /api/info` | hostname (pod name), version, colour |
| `GET /api/burn?seconds=30` | CPU stress → triggers HPA |
| `GET /q/health` | liveness + readiness probes |
| `GET /q/metrics` | Prometheus metrics (Micrometer) |
| `GET /swagger-ui` | OpenAPI UI |

---

## 📌 Recap

| Έδειξα | Μήνυμα |
|--------|--------|
| Import from Git | Το μόνο που χρειάζεται ο developer |
| Auto-detection | Το platform καταλαβαίνει το framework |
| Build logs live | Διαφάνεια — ξέρεις τι συμβαίνει |
| App live in browser | End-to-end σε λεπτά |

---

## ➡️ Next: [Pods / Service / Route](03-pods-svc-route.md)

# ACT 2 — Deploy with S2I

> **Overview:** OpenShift deploys a Quarkus application directly from source code, with no Dockerfile and no manual container build steps.

---

## What is S2I?

**Source-to-Image (S2I)** is an OpenShift build mechanism that:

1. Accepts a **source code repository** (Git URL)
2. Auto-detects the **language / framework**
3. Produces a **container image** — no Dockerfile required
4. **Deploys** the image and exposes a live HTTPS URL

> **Key point:** S2I abstracts the container build pipeline. Developers provide source; the platform handles the rest.

---

## Steps

### 1. Import from Git

**+Add → Import from Git**

---

### 2. Git URL

```
https://github.com/tses/quarkus-demo
```

Sub-directory (context dir): `app/ocp-demo-app`

> **Tip:** The console validates the URL and auto-detects the builder image before proceeding.

> **Note:** Auto-detection reads the project structure (e.g. `pom.xml`) to select the correct builder — in this case `java:openjdk-17-ubi8`.

---

### 3. Auto-populated fields

| Field | Value | Notes |
|---|---|---|
| Builder Image | `java:openjdk-17-ubi8` | Auto-detected from source |
| Application Name | `ocp-demo-app` | Editable |
| Resource type | `Deployment` | Default — suitable for stateless apps |
| Create a Route | ✅ | HTTPS exposure enabled by default |

> **Tip:** All fields are editable. The defaults are correct for this application.

---

### 4. Build Pipeline

After clicking **Create**, a build spinner appears on the app node in **Topology**.

Selecting the app node and opening **View Logs** (Build tab) shows the S2I build pipeline live: dependency download → compile → image assembly. This is the same process a CI/CD pipeline automates.

**⏳ Allow the build log to stream fully — it makes the process transparent.**

---

### 5. Build completes → Pod starts → Route is live

Once the build completes, the Topology view updates:

- The build pod disappears
- The app pod appears (dark blue ring = running and healthy)
- The Route URL appears (top-right arrow icon on the node)

The **Route URL** opens the application at `/api/info`.

> **Key point:** From a Git URL to a live, load-balanced HTTPS endpoint — no infrastructure tickets, no Dockerfile, no manual image push.

---

## CLI Equivalent (`scripts/02-deploy-s2i.sh`)

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

> **Tip:** Three commands — equivalent to the console flow. CI/CD pipelines run exactly this sequence.

---

## App Endpoints

| Endpoint | Description |
|---|---|
| `GET /api/info` | Pod hostname, version, colour |
| `GET /api/burn?seconds=30` | CPU stress — used to trigger HPA in Act 3 |
| `GET /q/health` | Liveness + readiness probe responses |
| `GET /q/metrics` | Prometheus metrics (Micrometer) |
| `GET /swagger-ui` | OpenAPI UI |

---

## Recap

| Demonstrated | Key point |
|---|---|
| Import from Git | Single input required from the developer |
| Auto-detection | Platform identifies framework and selects builder |
| Live build logs | Full build transparency — auditable |
| App live in browser | End-to-end deployment in minutes |

---

## ➡️ Next: [Pods / Service / Route](03-pods-svc-route.md)

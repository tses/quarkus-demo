# ACT 2 — Pods / Service / Route

> **Goal:** Establish a clear mental model of the three core Kubernetes networking primitives before exploring them in the console.

---

## The Three Primitives

**30-second mental model — establish this before touching the UI:**

```
Pod          → the running process (your app, in a container)
Service      → stable internal address for a group of pods
Route        → public URL that points to the Service
```

> **Tip:** An analogy: Pod = the kitchen, Service = the order counter, Route = the front door. The kitchen changes; the counter address stays the same.

---

## Steps

### 1. Topology View — The Live Diagram

Navigate to: **Topology**

Point out:
- The app node (circle) — click to expand
- **Dark blue ring** = pod is running and healthy
- **Arrow icon** (top-right of node) = Route URL

> **Take away:** The Topology view is not a static diagram. It reflects actual cluster state — updated in real time as pods start, stop, or fail.

---

### 2. Click the App Node → Side Panel

Show the side panel tabs:

- **Details** — replicas, labels, image reference
- **Resources** — pod list, services, routes
- **Observe** — inline metrics preview

Click on the **Pod name** in the Resources tab.

---

### 3. Inside the Pod

Navigate to: Pod detail page

Show tabs:

- **Details** — which node it runs on, current status, pod IP
- **Logs** — live application output
- **Terminal** — interactive shell into the running container

```bash
# Terminal tab — shell into the running container
ls /deployments
cat /etc/os-release
```

> **Gotcha:** Browser-based shell access requires no SSH and no VPN. This is the standard debugging path for containerised workloads — not a workaround.

---

### 4. Show the Service

Navigate to: **Project → Services** (or via Resources tab)

```bash
# CLI equivalent
oc get svc
oc describe svc ocp-demo-app
```

Point out:

- `ClusterIP` — internal address only, not reachable from outside the cluster
- Port mapping
- `selector` field — how the Service identifies its target pods

> **Gotcha:** A Service has no direct knowledge of specific pods. It queries: *"which pods carry this label?"* — and routes to whatever matches. This is label-based discovery, not hardcoded references.

---

### 5. Show the Route

Navigate to: **Networking → Routes**

```bash
# CLI equivalent
oc get route ocp-demo-app
oc describe route ocp-demo-app
```

Point out:

- **TLS termination** — HTTPS enabled automatically ✅
- Host URL pattern: `<app>-<project>.<cluster-domain>`

> **Take away:** HTTPS termination requires zero manual certificate management. The cluster handles provisioning and renewal.

---

## Recap

| Concept | Mental model | Key behaviour |
|---|---|---|
| Pod | Running process | Ephemeral — can be replaced at any time |
| Service | Stable endpoint | Always addressable — decouples clients from pod lifecycle |
| Route | Public ingress | HTTPS automatic — no cert management required |

---

## ➡️ Next: [Deployment Strategies](04-deployment-strategies.md)

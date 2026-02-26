# ACT 2 — Pods / Service / Route

> **Overview:** Three core Kubernetes networking primitives — Pod, Service, and Route — form the foundation of application networking in OpenShift.

---

## The Three Primitives

```
Pod          → the running process (your app, in a container)
Service      → stable internal address for a group of pods
Route        → public URL that points to the Service
```

> **Analogy:** Pod = the kitchen, Service = the order counter, Route = the front door. The kitchen changes; the counter address stays the same.

---

## Steps

### 1. Topology View — The Live Diagram

**Topology**

The app node (circle) expands to reveal:
- **Dark blue ring** = pod is running and healthy
- **Arrow icon** (top-right of node) = Route URL

> **Key point:** The Topology view is not a static diagram. It reflects actual cluster state — updated in real time as pods start, stop, or fail.

---

### 2. App Node Side Panel

Clicking the app node opens a side panel with the following tabs:

- **Details** — replicas, labels, image reference
- **Resources** — pod list, services, routes
- **Observe** — inline metrics preview

The **Pod name** in the Resources tab links to the Pod detail page.

---

### 3. Inside the Pod

The Pod detail page provides:

- **Details** — which node it runs on, current status, pod IP
- **Logs** — live application output
- **Terminal** — interactive shell into the running container

```bash
# Terminal tab — shell into the running container
ls /deployments
cat /etc/os-release
```

> **Note:** Browser-based shell access requires no SSH and no VPN. This is the standard debugging path for containerised workloads.

---

### 4. The Service

**Project → Services** (or via the Resources tab)

```bash
# CLI equivalent
oc get svc
oc describe svc ocp-demo-app
```

Key fields:

- `ClusterIP` — internal address only, not reachable from outside the cluster
- Port mapping
- `selector` field — how the Service identifies its target pods

> **Note:** A Service has no direct knowledge of specific pods. It queries: *"which pods carry this label?"* — and routes to whatever matches. This is label-based discovery, not hardcoded references.

---

### 5. The Route

**Networking → Routes**

```bash
# CLI equivalent
oc get route ocp-demo-app
oc describe route ocp-demo-app
```

Key fields:

- **TLS termination** — HTTPS enabled automatically ✅
- Host URL pattern: `<app>-<project>.<cluster-domain>`

> **Key point:** HTTPS termination requires zero manual certificate management. The cluster handles provisioning and renewal.

---

## Recap

| Concept | Mental model | Key behaviour |
|---|---|---|
| Pod | Running process | Ephemeral — can be replaced at any time |
| Service | Stable endpoint | Always addressable — decouples clients from pod lifecycle |
| Route | Public ingress | HTTPS automatic — no cert management required |

---

## ➡️ Next: [Deployment Strategies](04-deployment-strategies.md)

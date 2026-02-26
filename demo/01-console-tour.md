# ACT 1 — Console Tour

> **Overview:** OpenShift 4.20 provides a unified console that combines Developer and Administrator capabilities into a single, streamlined view.

---

## Overview

OpenShift 4.20 has a **unified console** that consolidates Developer and Administrator capabilities into a single, streamlined view:

- **Unified perspective** — topology, workloads, nodes, quotas, operators, and cluster health are all accessible from one place
- **Unified software catalog** — the developer catalog and Operators are available from a single location

> **Note:** The unified-perspective design is a deliberate UX choice — not cosmetic — eliminating context-switching between developer and admin tasks. Users familiar with other Kubernetes UIs may expect separate views; OpenShift consolidates them intentionally.

---

## Steps

### 1. Open the Console

```
https://<your-cluster-console-url>
```

> **Tip:** Bookmark this URL. Everything available via the `oc` CLI is also accessible here, against the same API.

---

### 2. The Unified Perspective

The top-left navigation provides a **single unified view** for all roles:

- Available sections include: Topology, Workloads, Networking, Storage, Compute, Operators, and Observe — all from the same console
- RBAC controls what each role can *act* on; the view itself is unified

> **Key point:** One console serves both developers and administrators. Everyone sees a cohesive view of the cluster; permissions determine what they can change.

---

### 3. Topology View

**Observe → Topology**

- The namespace is initially empty (populated in Act 2)
- The topology view supports drag-and-drop layout, visual grouping, and live health indicators

> **Key point:** The Topology view reflects the live state of every deployed workload — connections, health, and routes — updated in real time.

---

### 4. Unified Software Catalog

**+Add → Software Catalog** (or the **Catalog** entry in the nav)

- The **developer catalog** and the **Operators** section are merged into a single location
- Helm charts, templates, Operator-backed services, and builder images are all browsable from one screen

> **Tip:** Developer catalog and Operators are in the same place — no separate navigation sections required.

---

### 5. Key Admin Sections

The following sections are available from the main navigation:

- **Compute → Nodes** — cluster nodes and their current status
- **Operators → Installed Operators** — revisited in Act 3
- **Observe → Dashboards** — revisited in Act 3

> **Note:** Cluster-level visibility is built into the console — not added via a separate tool or plugin.

---

### 6. The `oc` CLI

```bash
oc login --server=https://<cluster-api-url> --token=<your-token>
oc whoami
oc get nodes
```

> **Key point:** The console and CLI are equivalent interfaces to the same Kubernetes API. Either can be used interchangeably — the underlying operations are identical.

---

## Recap

| Demonstrated | Key point |
|---|---|
| Unified perspective | One console for all roles — developers and admins in the same view |
| Unified software catalog | Developer catalog + Operators in one location |
| Topology view | Live application graph — populated in the next step |
| Nodes & Operators | Infrastructure is present and managed |
| `oc` CLI | Console and CLI share the same API surface |

---

## ➡️ Next: [Deploy with S2I](02-deploy-s2i.md)

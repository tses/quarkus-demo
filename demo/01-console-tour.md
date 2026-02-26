# ACT 1 — Console Tour

> **Goal:** Orient the audience to the OpenShift 4.20 unified console before any hands-on work begins.

---

## Goal

Show that OpenShift 4.20 has a **unified console** that combines Developer and Administrator capabilities into a single, streamlined view:

- **Unified perspective** — topology, workloads, nodes, quotas, operators, and cluster health all in one place
- **Unified software catalog** — developer catalog and Operators accessible from a single location

> **Gotcha:** Most people expect "just another kubectl UI". The unified-perspective design is a deliberate UX choice — not cosmetic — eliminating context-switching between developer and admin tasks.

---

## Steps

### 1. Open the Console

```
https://<your-cluster-console-url>
```

> **Tip:** Bookmark this URL. Everything you can do with `oc` CLI can also be done here, against the same API.

---

### 2. Show the Unified Perspective

The top-left nav provides a **single unified view** for all roles:

- Navigate across: Topology, Workloads, Networking, Storage, Compute, Operators, Observe — all from the same console
- RBAC still controls what each role can *act* on

> **Take away:** One console for developers and administrators alike. Everyone sees a cohesive view of the cluster; permissions determine what they can change.

---

### 3. Topology View

Navigate to: **Observe → Topology**

- Empty namespace for now (populated in Act 2)
- Drag-and-drop layout, visual grouping, live health indicators

> **Goal:** This view reflects the live state of every deployed workload — connections, health, and routes — updated in real time.

---

### 4. Unified Software Catalog

Navigate to: **+Add → Software Catalog** (or the **Catalog** entry in the nav)

- The **developer catalog** and the **Operators** section are merged into a single location
- Browse Helm charts, templates, Operator-backed services, and builder images all from one screen

> **Tip:** Developer catalog and Operators are now in the same place — no need to navigate to separate sections.

---

### 5. Quick Tour of Key Admin Sections

Navigate briefly to:
- **Compute → Nodes** — cluster nodes and their current status
- **Operators → Installed Operators** — revisited in Act 3
- **Observe → Dashboards** — revisited in Act 3

> **Tip:** No need to memorise these paths now. The intent is to show that cluster-level visibility is built in, not bolted on.

---

### 6. Show the `oc` CLI (terminal)

```bash
oc login --server=https://<cluster-api-url> --token=<your-token>
oc whoami
oc get nodes
```

> **Take away:** Console and CLI are equivalent interfaces to the same Kubernetes API. This demo uses both — choose whichever fits your workflow.

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

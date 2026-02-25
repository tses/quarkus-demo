# ACT 1 — Console Tour

> **Duration:** ~10 minutes  
> **Wow Factor:** "Υπάρχει ένα UI που καταλαβαίνει και τον developer και τον admin"  
> **Message:** Orientation — το κοινό νιώθει σπίτι πριν αρχίσει το action.

---

## 🎯 Goal of This Section

Show that OpenShift has **two distinct perspectives** built into the same console:
- **Developer** view — topology, app-centric, visual
- **Administrator** view — nodes, quotas, operators, cluster health

This alone surprises people who expect "just another kubectl UI".

---

## 🖥️ Steps

### 1. Open the Console
```
https://<your-cluster-console-url>
```
> 💬 *"Αυτή είναι η κονσόλα του OpenShift. Δεν είναι dashboard. Είναι ο κεντρικός χειριστής του platform."*

---

### 2. Show the Perspective Switcher (top-left dropdown)

Switch between:
- `Developer` perspective
- `Administrator` perspective

> 💬 *"Ο developer βλέπει τις εφαρμογές του. Ο admin βλέπει το cluster. Ίδια κονσόλα, διαφορετικός φακός."*

---

### 3. Developer Perspective — Topology View

Navigate to: **Developer → Topology**

- Empty namespace for now (we'll fill it in Act 2)
- Point out: drag-and-drop layout, visual grouping, live health indicators

> 💬 *"Αυτό που θα δείτε εδώ σε λίγο είναι η εφαρμογή μας — ζωντανή, με connections, με health status."*

---

### 4. Administrator Perspective — Quick Tour

Navigate briefly to:
- **Compute → Nodes** — show the cluster nodes, their status
- **Operators → Installed Operators** — "θα γυρίσουμε εδώ αργότερα"
- **Observe → Dashboards** — "και εδώ"

> 💬 *"Δεν χρειάζεται να θυμάστε αυτά τώρα. Απλώς να ξέρετε ότι υπάρχουν. Θα τα δούμε όλα."*

---

### 5. Show the `oc` CLI (terminal)

```bash
oc login --server=https://<cluster-api-url> --token=<your-token>
oc whoami
oc get nodes
```

> 💬 *"Ό,τι βλέπετε στην κονσόλα, μπορείτε να το κάνετε και από terminal. Ίδιο API. Θα χρησιμοποιήσουμε και τα δύο."*

---

## 📌 Recap

| Έδειξα | Μήνυμα |
|--------|--------|
| Perspective switcher | Developer ≠ Admin view — ο καθένας βλέπει αυτό που χρειάζεται |
| Topology (empty) | Εδώ θα "ζει" η εφαρμογή μας |
| Nodes & Operators | Η υποδομή είναι εκεί, managed |
| `oc` CLI | Console και CLI είναι ισοδύναμα |

---

## ➡️ Next: [Deploy with S2I](02-deploy-s2i.md)

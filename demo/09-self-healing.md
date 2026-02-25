# ACT 3 — Self-Healing Pods

> **Duration:** ~4 minutes  
> **Script:** `scripts/09-self-healing.sh`  
> **Wow Factor:** Kill a pod live — it comes back on its own. Audience watches it happen.  
> **Message:** *"Το platform δεν κοιμάται. Παρακολουθεί. Διορθώνει. Μόνο του."*

---

## 🎯 Mental Model First

> 💬 *"Σε ένα κλασικό server: αν κρασάρει η εφαρμογή, κάποιος λαμβάνει alert, κάποιος ξυπνά, κάποιος κάνει restart. Με OpenShift — αυτός ο κάποιος είναι το platform."*

OpenShift runs a **reconciliation loop** continuously:

```
Desired state:  3 pods running
Actual state:   2 pods running (one died)
Action:         Create new pod immediately
```

This is the **self-healing** guarantee built into Kubernetes/OpenShift.

---

## 🖥️ Steps

### 1. Starting state — 3 pods running

Script 08 ends with 3 replicas — this demo starts directly from that state.

```bash
oc get pods -l app=ocp-demo-app -n ocp-demo
```

Point to the **dark blue rings** on all pods.

> 💬 *"Τρία pods. Όλα healthy. Ας δούμε τι γίνεται αν ένα 'πεθάνει'."*

---

### 2. Open a split view (CLI + Console)

- **Left screen / tab:** Topology view (watching visually)
- **Right screen / tab:** Terminal running the script

---

### 3. ⚡ THE MOMENT — Kill a pod

The script highlights the pod about to be deleted:

```
╔══════════════════════════════════════╗
║   KILLING POD: ocp-demo-app-xxx...   ║
╚══════════════════════════════════════╝
```

```bash
oc delete pod <pod-name> -n ocp-demo
```

**Immediately switch attention to the Topology view.**

> 💬 *"Σκότωσα το pod. Μπροστά σας."*

**Pause. Let the audience watch.**

---

### 4. Watch it recover in real-time

The script polls every 2 seconds for 30 seconds:

```
[t+2s]  Running pods: 2/3
[t+4s]  Running pods: 2/3
[t+6s]  Running pods: 3/3  ✅
```

> 💬 *"Είδατε; Δύο δευτερόλεπτα. Το platform το είδε. Έφτιαξε νέο pod. Η εφαρμογή δεν είδε ποτέ downtime."*

---

### 5. Show the new pod (different name = genuinely new)

```bash
oc get pods -l app=ocp-demo-app -n ocp-demo
# NAME                        STATUS    RESTARTS   AGE
# ocp-demo-app-xxx-abc12      Running   0          12m
# ocp-demo-app-xxx-def34      Running   0          12m
# ocp-demo-app-xxx-xyz99      Running   0          8s   ← NEW
```

> 💬 *"Νέο pod. Νέο όνομα. Ίδια εφαρμογή. Αυτό συμβαίνει automatically, 24/7, 365 ημέρες."*

---

### 6. Verify — app never went down

```bash
curl http://<route>/api/info   # still responds — no downtime
```

---

## 🎬 Closing Line for the Entire Demo

> 💬 *"Αυτό που είδατε σήμερα — S2I, canary deployments, self-healing, monitoring, operators — δεν είναι το μέλλον. Τρέχει σε production, σε εταιρείες που γνωρίζετε, σήμερα. Το ερώτημα δεν είναι 'αν'. Είναι 'πότε'."*

---

## 📌 The Full Arc — Recap

| What happened | Why it matters |
|--------------|----------------|
| Git URL → Live HTTPS app (S2I) | Developer productivity × 10 |
| Traffic split with weights | Zero-risk production releases |
| Pod killed → auto-replaced | No on-call for crashes |

---

## 🏁 End of Demo

Thank the audience. Open for Q&A.

Suggested follow-up actions:
- **Red Hat Developer Sandbox** (free): [developers.redhat.com/developer-sandbox](https://developers.redhat.com/developer-sandbox)
- **OpenShift Interactive Learning** (free, browser-based labs): [developers.redhat.com/learn](https://developers.redhat.com/learn)
- Internal next step: pilot project scoping session

# ACT 3 — Self-Healing Pods ⭐ WOW #3

> **Duration:** ~4 minutes  
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

## 🖥️ Steps — The Most Dramatic 4 Minutes of the Demo

### 1. Setup — Show the running state

Navigate to: **Developer → Topology → App Node**

Make sure you have **2-3 replicas** running (scale up if needed):

```bash
oc scale deployment/my-app --replicas=3
```

Point to the **dark blue rings** on all pods.

> 💬 *"Τρία pods. Όλα healthy. Ας δούμε τι γίνεται αν ένα 'πεθάνει'."*

---

### 2. Open a split view (CLI + Console)

- **Left screen / tab:** Topology view (watching visually)
- **Right screen / tab:** Terminal

In the terminal, get the pod names:

```bash
oc get pods -l app=my-app
```

Example output:
```
NAME                       READY   STATUS    RESTARTS   AGE
my-app-7d9f8b6c4-abc12    1/1     Running   0          10m
my-app-7d9f8b6c4-def34    1/1     Running   0          10m
my-app-7d9f8b6c4-ghi56    1/1     Running   0          10m
```

---

### 3. ⚡ THE MOMENT — Kill a pod

```bash
oc delete pod my-app-7d9f8b6c4-abc12
```

**Immediately switch attention to the Topology view.**

> 💬 *"Σκότωσα το pod. Μπροστά σας."*

**Pause. Let the audience watch.**

The pod ring briefly goes from 3 → 2 → back to 3 (new pod created and goes Running).

> 💬 *"Είδατε; Δύο δευτερόλεπτα. Το platform το είδε. Έφτιαξε νέο pod. Η εφαρμογή δεν είδε ποτέ downtime."*

---

### 4. Show the new pod (different name, same app)

```bash
oc get pods -l app=my-app
```

The new pod has a **different random suffix** — it's genuinely a new pod.

```
NAME                       READY   STATUS    RESTARTS   AGE
my-app-7d9f8b6c4-def34    1/1     Running   0          11m
my-app-7d9f8b6c4-ghi56    1/1     Running   0          11m
my-app-7d9f8b6c4-xyz99    1/1     Running   0          8s   ← NEW
```

> 💬 *"Νέο pod. Νέο όνομα. Ίδια εφαρμογή. Αυτό συμβαίνει automatically, 24/7, 365 ημέρες."*

---

### 5. (Optional Power Move) — Simulate crash loop

```bash
# Force a crash by running an invalid command inside a pod
oc exec my-app-7d9f8b6c4-def34 -- kill 1
```

Watch the RESTARTS counter go up:

```bash
oc get pods -l app=my-app -w
```

> 💬 *"'Restarts: 1' — το platform ξέρει ότι κάτι δεν πάει καλά. Αν συνεχίσει να κρασάρει, μπαίνει σε CrashLoopBackOff — το platform σας λέει: 'κάτι πρέπει να διορθωθεί στον κώδικα.'"*

---

## 🎬 Closing Line for the Entire Demo

After this moment, close with:

> 💬 *"Αυτό που είδατε σήμερα — S2I, canary deployments, self-healing, monitoring, operators — δεν είναι το μέλλον. Τρέχει σε production, σε εταιρείες που γνωρίζετε, σήμερα. Το ερώτημα δεν είναι 'αν'. Είναι 'πότε'."*

---

## 📌 The Full Wow Arc — Recap

| WOW # | What happened | Why it matters |
|-------|--------------|----------------|
| ⭐ WOW #1 | Git URL → Live HTTPS app | Developer productivity × 10 |
| ⭐ WOW #2 | Traffic split with weights | Zero-risk production releases |
| ⭐ WOW #3 | Pod killed → auto-replaced | No on-call for crashes |

---

## 🏁 End of Demo

Thank the audience. Open for Q&A.

Suggested follow-up actions to offer:
- Access to **Red Hat Developer Sandbox** (free): [developers.redhat.com/developer-sandbox](https://developers.redhat.com/developer-sandbox)
- **OpenShift Interactive Learning** (free, browser-based labs): [developers.redhat.com/learn](https://developers.redhat.com/learn)
- Internal next step: pilot project scoping session

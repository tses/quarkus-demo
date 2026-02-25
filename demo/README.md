# 🚀 OpenShift Introduction — Hands-On Demo Guide

> **Audience:** Ops/Sysadmins & Developers with no prior OpenShift experience  
> **Format:** Instructor-led live demo (no participant access required)  
> **Goal:** Inspire — show what's possible, not just what exists  
> **Total Time:** ~60–75 minutes

---

## 🎭 The Story We're Telling

> *"From source code on GitHub to a production-grade, self-healing, observable, 
> zero-downtime-deployable application — in under 10 minutes."*

Every step is a deliberate **"wow moment"**. Pace yourself. Let the audience absorb each one.

---

## 🏗️ Demo Arc — Three Acts

| Act | Theme | Message | Duration |
|-----|-------|---------|----------|
| **ACT 1** | Orientation | *"This platform has a cockpit — and it makes sense"* | ~10 min |
| **ACT 2** | Magic | *"Code → Running App. No Dockerfile. No YAML. No ops ticket."* | ~20 min |
| **ACT 3** | Power | *"Features that would take months to build — out of the box"* | ~35 min |

---

## 📋 Demo Steps

| # | Step | Section | Wow Factor | Time |
|---|------|---------|------------|------|
| 1 | [Console Tour](01-console-tour/README.md) | ACT 1 | Developer & Admin perspectives | 10 min |
| 2 | [Deploy with S2I](02-deploy-s2i/README.md) | ACT 2 | ⭐ **WOW #1** — Git URL → Live App | 10 min |
| 3 | [Pods / Service / Route](03-pods-svc-route/README.md) | ACT 2 | Topology view, live URL | 10 min |
| 4 | [Deployment Strategies](04-deployment-strategies/README.md) | ACT 3 | Rolling vs Recreate — visual | 8 min |
| 5 | [Traffic Splitting](05-traffic-splitting/README.md) | ACT 3 | ⭐ **WOW #2** — Canary with a slider | 8 min |
| 6 | [Deploy Postgres Operator](06-operator-postgres/README.md) | ACT 3 | Production DB in 2 clicks | 8 min |
| 7 | [Monitoring (Grafana OTB)](07-monitoring/README.md) | ACT 3 | Dashboards — zero config | 5 min |
| 8 | [Scaling Out](08-scaling/README.md) | ACT 3 | HPA — auto-scale under load | 5 min |
| 9 | [Self-Healing Pods](09-self-healing/README.md) | ACT 3 | ⭐ **WOW #3** — Kill it, it comes back | 4 min |

---

## ⭐ The Three Wow Moments (Plan These Carefully)

### WOW #1 — S2I: "Zero to App"
**Setup:** Have the GitHub repo URL ready in a browser tab.  
**Line to say:** *"Βλέπετε; Δίνω μόνο το URL του repo. Δεν έγραψα Dockerfile. Δεν έφτιαξα YAML. Το OpenShift καταλαβαίνει ότι είναι Quarkus και το χτίζει μόνο του."*  
**Wait for:** Build logs streaming in the console. Let them watch. Don't skip.

### WOW #2 — Traffic Splitting: "Canary Release Live"
**Setup:** Have v1 deployed and v2 image ready.  
**Line to say:** *"Αυτό είναι canary deployment. Στέλνουμε 10% της κίνησης στη νέα έκδοση. Αν κάτι πάει στραβά — πίσω με ένα κλικ. Χωρίς downtime. Χωρίς engineer on call."*  
**Wait for:** The traffic weight slider — move it slowly. Visually dramatic.

### WOW #3 — Self-Healing: "The Platform Watches"
**Setup:** App is running, show pod list.  
**Line to say:** *"Θα σκοτώσω το pod. Μπροστά σας."* [delete pod] *"Βλέπετε; Το platform το είδε. Έφτιαξε νέο. Η εφαρμογή δεν είδε ποτέ downtime."*  
**Wait for:** Pod count back to desired state. Dramatic pause before speaking again.

---

## 🛠️ Prerequisites & Pre-Demo Checklist

Before entering the room, verify:

- [ ] `oc login` works on your machine
- [ ] Project/namespace created: `oc new-project ocp-demo`
- [ ] GitHub repo URL copied and ready (Quarkus app)
- [ ] Browser tabs pre-opened: OCP Console, your GitHub repo, app URL (empty — will fill during demo)
- [ ] v1 and v2 container images available (for traffic splitting)
- [ ] OperatorHub accessible (for Postgres operator)
- [ ] Screen font size increased for readability (min 16pt terminal)
- [ ] Notifications silenced 🔇

---

## 💬 Key Phrases Bank

Use these intentionally — they encode the message:

| Context | Say this |
|---------|----------|
| Opening | *"Ξεχάστε το 'it works on my machine'. Μιλάμε για ένα platform που το κάνει standard."* |
| After S2I | *"Αυτό που μόλις είδατε, σε ένα κλασικό setup παίρνει sprint να στηθεί."* |
| After self-healing | *"Ο platform engineer σας κοιμάται ήσυχος."* |
| Closing | *"Αυτό δεν είναι το μέλλον. Τρέχει production σήμερα, σε εταιρείες που γνωρίζετε."* |

---

## 📁 Project Structure

```
demo/
├── README.md                    ← You are here (master guide)
├── 01-console-tour/README.md
├── 02-deploy-s2i/README.md
├── 03-pods-svc-route/README.md
├── 04-deployment-strategies/README.md
├── 05-traffic-splitting/README.md
├── 06-operator-postgres/README.md
├── 07-monitoring/README.md
├── 08-scaling/README.md
└── 09-self-healing/README.md
```

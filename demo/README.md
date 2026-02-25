# 🚀 OpenShift Introduction — Hands-On Demo Guide

> **Audience:** Ops/Sysadmins & Developers with no prior OpenShift experience  
> **Format:** Instructor-led live demo (no participant access required)  
> **Goal:** Show what's possible — platform capabilities, not just features  
> **Total Time:** ~60–75 minutes

---

## 🎭 The Story We're Telling

> *"From source code on GitHub to a production-grade, self-healing, observable, 
> zero-downtime-deployable application — in under 10 minutes."*

Every step has a deliberate message. Pace yourself. Let the audience absorb each one.

---

## 🏗️ Demo Arc — Three Acts

| Act | Theme | Message | Duration |
|-----|-------|---------|----------|
| **ACT 1** | Orientation | *"This platform has a cockpit — and it makes sense"* | ~10 min |
| **ACT 2** | Build & Deploy | *"Code → Running App. No Dockerfile. No YAML. No ops ticket."* | ~20 min |
| **ACT 3** | Platform Power | *"Features that would take months to build — out of the box"* | ~35 min |

---

## 📋 Demo Steps

| # | Step | Section | Time |
|---|------|---------|------|
| 1 | [Console Tour](01-console-tour.md) | ACT 1 | 10 min |
| 2 | [Deploy with S2I](02-deploy-s2i.md) | ACT 2 | 10 min |
| 3 | [Pods / Service / Route](03-pods-svc-route.md) | ACT 2 | 10 min |
| 4 | [Deployment Strategies](04-deployment-strategies.md) | ACT 3 | 8 min |
| 5 | [Traffic Splitting](05-traffic-splitting.md) | ACT 3 | 8 min |
| 6 | [Deploy Postgres Operator](06-operator-postgres.md) | ACT 3 | 8 min |
| 7 | [Monitoring](07-monitoring.md) | ACT 3 | 5 min |
| 8 | [Scaling Out](08-scaling.md) | ACT 3 | 5 min |
| 9 | [Self-Healing Pods](09-self-healing.md) | ACT 3 | 4 min |

---

## 🛠️ Prerequisites & Pre-Demo Checklist

Before entering the room, verify:

- [ ] `oc login` works on your machine
- [ ] Project/namespace created: `oc new-project ocp-demo`
- [ ] GitHub repo URL ready: `https://github.com/tses/quarkus-demo`
- [ ] Browser tabs pre-opened: OCP Console, GitHub repo
- [ ] OperatorHub accessible (for Postgres operator)
- [ ] Screen font size increased for readability (min 16pt terminal)
- [ ] Notifications silenced 🔇

---

## 💬 Key Phrases Bank

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
├── README.md                      ← You are here (master guide)
├── 01-console-tour.md
├── 02-deploy-s2i.md
├── 03-pods-svc-route.md
├── 04-deployment-strategies.md
├── 05-traffic-splitting.md
├── 06-operator-postgres.md
├── 07-monitoring.md
├── 08-scaling.md
└── 09-self-healing.md
```

# OpenShift Introduction — Hands-On Demo Guide

> **Audience:** Ops/Sysadmins & Developers with no prior OpenShift experience
> **Format:** Instructor-led live demo (no participant cluster access required)
> **Goal:** Demonstrate platform capabilities end-to-end — from source code to a production-grade, observable, self-healing application
> **Total Time:** ~60–75 minutes

---

## Demo Narrative

> *"From a Git URL to a production-grade, self-healing, observable, zero-downtime-deployable application — in under 10 minutes. The remaining 60 minutes show what the platform does for you after that."*

Each step has a deliberate technical message. Maintain pace discipline — allow the audience time to register each point before advancing.

---

## Demo Arc — Three Acts

| Act | Theme | Message |
|---|---|---|
| **ACT 1** | Orientation | The platform has a structured cockpit — distinct views for developers and administrators |
| **ACT 2** | Build & Deploy | Source code to running application — no Dockerfile, no YAML, no infrastructure ticket |
| **ACT 3** | Platform Capabilities | Production features that would require months of custom tooling — built in and operational by default |

---

## Demo Steps

| # | Step | Act | Time |
|---|---|---|---|
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

## Prerequisites & Pre-Demo Checklist

Verify the following before starting:

- [ ] `oc login` succeeds on the demo machine
- [ ] Project/namespace exists: `oc new-project ocp-demo`
- [ ] GitHub repo URL accessible: `https://github.com/tses/quarkus-demo`
- [ ] Browser tabs pre-opened: OCP Console, GitHub repo
- [ ] OperatorHub accessible (required for Postgres operator section)
- [ ] Terminal font size set for readability (minimum 16pt)
- [ ] System notifications silenced 🔇

---

## Key Talking Points

| Context | Point |
|---|---|
| Opening | The platform standardises what "it works in production" means — not just on one machine. |
| After S2I | The same three CLI commands run in any CI/CD pipeline. The console is one interface to the same API. |
| After self-healing | The reconciliation loop runs continuously — not on a cron schedule, not triggered by an alert. |
| Closing | These are production-deployed capabilities in use at scale today. The adoption question is one of timing. |

---

## Project Structure

```
demo/
├── README.md                      ← Master guide (this file)
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

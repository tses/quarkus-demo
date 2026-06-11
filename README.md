# OpenShift Introduction — Hands-On Demo Guide

> **Audience:** Ops/Sysadmins & Developers with no prior OpenShift experience
> **Format:** Instructor-led live demo (no participant cluster access required)
> **Goal:** Demonstrate platform capabilities end-to-end — from source code to a production-grade, observable, self-healing and securely exposed application
> **Total Time:** ~120–145 minutes

---

## Demo Narrative

This demo provides a structured introduction to the OpenShift platform for both technical and operational audiences, showing how an application moves from source code to a running service and then how the platform supports real production needs through deployment automation, routing, rollout strategies, health checks, resource controls, monitoring, scaling, and self-healing capabilities. Rather than presenting isolated features, it walks through a complete application lifecycle so the audience can understand how OpenShift brings developer workflows and day-2 operations together in a single, production-ready platform.



---

## Demo Arc — Four Acts

| Act | Theme | Message |
|---|---|---|
| **ACT 1** | Orientation | OpenShift 4.20 provides a unified console with distinct views for developers and administrators |
| **ACT 2** | Build & Deploy | Source code to running application — no Dockerfile, no YAML, no infrastructure ticket |
| **ACT 3** | Platform Capabilities | Production features that would require months of custom tooling — built in and operational by default |
| **ACT 4** | Connectivity Link | Secure, protect and observe application connectivity with Gateway API and policy-driven controls |

---

## Demo Steps

| # | Step | Script | Act | Time |
|---|---|---|---|---|
| 1 | [Console Tour](01-console-tour.md) | _(console only)_ | ACT 1 | 10 min |
| 2 | [Deploy with S2I](02-deploy-s2i.md) | `scripts/02-deploy-s2i.sh` | ACT 2 | 10 min |
| 3 | [Pods / Service / Route](03-pods-svc-route.md) | `scripts/03-pods-svc-route.sh` | ACT 2 | 10 min |
| 4 | [Deployment Strategies](04-deployment-strategies.md) | `scripts/04-deployment-strategies.sh` | ACT 3 | 8 min |
| 5 | [Traffic Splitting](05-traffic-splitting.md) | `scripts/05-traffic-splitting.sh` | ACT 3 | 8 min |
| 6 | [Deploy Postgres Operator](06-operator-postgres.md) | `scripts/06-operator-postgres.sh` | ACT 3 | 8 min |
| 7 | [Health Probes](07-probes.md) | `scripts/07-probes.sh` | ACT 3 | 7 min |
| 8 | [Resource Requests & Limits](08-resources.md) | `scripts/08-resources.sh` | ACT 3 | 7 min |
| 9 | [Monitoring — ServiceMonitor](09-monitoring.md) | `scripts/09-monitoring.sh` | ACT 3 | 5 min |
| 10 | [Scaling Out](10-scaling.md) | `scripts/10-scaling.sh` | ACT 3 | 5 min |
| 11 | [Self-Healing Pods](11-self-healing.md) | `scripts/11-self-healing.sh` | ACT 3 | 4 min |
| 12 | [Gateway API Introduction](12-gateway-api.md) | `scripts/12-gateway-api.sh` | ACT 4 | 8 min |
| 13 | [Expose Application with HTTPRoute](13-http-route.md) | `scripts/13-http-route.sh` | ACT 4 | 8 min |
| 14 | [Secure Traffic with TLSPolicy](14-tls-policy.md) | `scripts/14-tls-policy.sh` | ACT 4 | 7 min |
| 15 | [Protect API with AuthPolicy](15-auth-policy.md) | `scripts/15-auth-policy.sh` | ACT 4 | 10 min |
| 16 | [Protect API with RateLimitPolicy](16-rate-limit-policy.md) | `scripts/16-rate-limit-policy.sh` | ACT 4 | 8 min |
| 17 | [Advanced Authorization with External Metadata](17-external-metadata.md) | `scripts/17-external-metadata.sh` | ACT 4 | 12 min |
| 18 | [Observe API Connectivity](18-connectivity-observability.md) | `scripts/18-connectivity-observability.sh` | ACT 4 | 6 min |
| 19 | [Future Extension — Multi-Cluster Connectivity](19-multicluster-future.md) | _(architecture only)_ | ACT 4 | 6 min |

---

## Prerequisites & Pre-Demo Checklist

Verify the following before starting:

- [ ] `oc login` succeeds on the demo machine
- [ ] Project/namespace exists: `oc new-project ocp-demo`
- [ ] GitHub repo URL accessible: `https://github.com/tses/quarkus-demo`
- [ ] Browser tabs pre-opened: OCP Console, GitHub repo
- [ ] OperatorHub accessible (required for Postgres operator section)
- [ ] Connectivity Link / Kuadrant components available (required for ACT 4)
- [ ] Gateway API resources available in the cluster
- [ ] cert-manager installed (cert-manager Operator for Red Hat OpenShift) — required for TLSPolicy (step 14)
- [ ] A Ready cert-manager issuer available (e.g. `self-signed` ClusterIssuer) for the Gateway certificate
- [ ] API key or JWT test credentials prepared for AuthPolicy demo
- [ ] External metadata service prepared for Authorino demo


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
├── 07-probes.md                   ← Liveness & readiness probes (live failure demo)
├── 08-resources.md                ← Resource requests & limits (CPU throttle demo)
├── 09-monitoring.md               ← ServiceMonitor / Prometheus scraping
├── 10-scaling.md                  ← Manual scale + HPA
├── 11-self-healing.md             ← Pod deletion + reconciliation loop
├── 12-gateway-api.md              ← Gateway API basics
├── 13-http-route.md               ← Expose app using HTTPRoute
├── 14-tls-policy.md               ← Secure Gateway traffic with TLSPolicy
├── 15-auth-policy.md              ← Protect API with AuthPolicy
├── 16-rate-limit-policy.md        ← Protect API with RateLimitPolicy
├── 17-external-metadata.md        ← Runtime authorization with external metadata
├── 18-connectivity-observability.md ← Observe protected API traffic
└── 19-multicluster-future.md      ← Future multi-cluster extension

scripts/
├── demo-config.sh                 ← Shared config and helper functions
├── 00-setup.sh
├── 02-deploy-s2i.sh
├── 03-pods-svc-route.sh
├── 04-deployment-strategies.sh
├── 05-traffic-splitting.sh
├── 06-operator-postgres.sh
├── 07-probes.sh                   ← Health probes
├── 08-resources.sh                ← Resource requests & limits
├── 09-monitoring.sh               ← ServiceMonitor
├── 10-scaling.sh                  ← Manual scale + HPA
├── 11-self-healing.sh             ← Self-healing demo
├── 12-gateway-api.sh              ← Gateway API basics
├── 13-http-route.sh               ← HTTPRoute exposure
├── 14-tls-policy.sh               ← TLSPolicy setup
├── 15-auth-policy.sh              ← AuthPolicy setup
├── 16-rate-limit-policy.sh        ← RateLimitPolicy setup
├── 17-external-metadata.sh        ← External metadata authorization
├── 18-connectivity-observability.sh ← Observability checks
└── 99-teardown.sh
```

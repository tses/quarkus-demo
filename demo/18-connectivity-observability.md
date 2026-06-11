# ACT 4 — Observe API Connectivity

> **Script:** `scripts/18-connectivity-observability.sh` — confirms observability is on, points at Grafana/Console, then drives steady traffic so the dashboards populate.
> **Overview:** Steps 13–17 put traffic through the Gateway and wrapped it in policies (TLS, Auth, RateLimit). This step shows **how to see that traffic**: the metrics, dashboards and traces Connectivity Link exposes out of the box.
> **Ref:** [Red Hat Connectivity Link 1.3 — Observability](https://docs.redhat.com/en/documentation/red_hat_connectivity_link/1.3/html-single/observability/index)

> **Note:** Live cluster setup (monitors, Grafana datasource, RBAC) lives in [`observability/how-to-setup-monitor.md`](../observability/how-to-setup-monitor.md). This guide explains **how it works**, not how to install it.

---

## How It Works in Connectivity Link

CL builds its observability on metrics that already exist on the cluster — it does **not** ship its own Prometheus or Grafana:

```
Envoy gateway (OpenShift Service Mesh)  → request metrics (istio_requests_total, latency…)
Gateway API + CL resources              → state metrics (policies enforced, ready…)
Kuadrant components                     → policy/runtime metrics
        ↓ scraped by
OpenShift user-workload monitoring (Prometheus / Thanos)
        ↓ queried by
Grafana → pre-built dashboards   |   Alertmanager → PrometheusRule alerts
```

> **Key point:** Turn on observability with **one switch** on the `Kuadrant` CR. CL then creates the `ServiceMonitor` / `PodMonitor` resources; the existing OpenShift monitoring stack does the scraping.

---

## The One Switch

```yaml
apiVersion: kuadrant.io/v1beta1
kind: Kuadrant
metadata:
  name: kuadrant
spec:
  observability:
    enable: true        # CL creates Service/PodMonitors for its components + gateways
```

Verify the monitors CL created:

```bash
oc get servicemonitor,podmonitor -A -l kuadrant.io/observability=true
```

---

## What You Get

| Feature | What it gives you |
|---|---|
| **Metrics** | Prometheus metrics for gateway + policy performance (via user-workload monitoring) |
| **Dashboards** | Pre-built Grafana dashboards — Platform Engineer, App Developer, Business User, DNS Operator |
| **Alerts** | Example `PrometheusRule` SLO/error-rate/latency alerts to adapt |
| **Tracing** | Control-plane (operator reconciliation) + data-plane (Envoy → Authorino → Limitador) via OpenTelemetry |
| **Access logs** | Structured Envoy logs, correlated by `x-request-id` |

### Grafana dashboards (import by ID)

> **Grafana:** <https://grafana-route-monitoring.apps.mini.azureuni.tses.gr/>

| Dashboard | ID |
|---|---|
| App Developer | `21538` |
| Platform Engineer | `20982` |
| Business User | `20981` |
| DNS Operator | `22695` |

> **Dashboard caveat:** for the per-app panels to populate, your `HTTPRoute` must carry `service` and `deployment` labels matching the backend — this joins low-level Envoy metrics with Gateway API state metrics.

---

## Demo Flow (talk-track)

1. **Show the switch** — `spec.observability.enable: true` on the `Kuadrant` CR; list the auto-created monitors.
2. **Open Grafana** — point at the Platform Engineer dashboard; explain it reads from Thanos via user-workload monitoring.
3. **Generate traffic** — the script fires a steady stream across the step-13/16 route and the step-17 per-tier route (mixing `200`/`429`/`403`) so request-rate, error-rate and throttling panels fill in. Re-run it to keep traffic flowing while touring the dashboards.
4. **Mention tracing & logs** — note that data-plane traces and `x-request-id` access logs let you follow one request through Envoy → Authorino → Limitador (setup-heavy, not shown live).

> **Why it's mostly setup:** the value here is that CL plugs into the **platform's** monitoring rather than reinventing it — once `enable: true` and the datasource are in place, observing connectivity is just opening a dashboard.

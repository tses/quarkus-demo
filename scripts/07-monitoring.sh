#!/usr/bin/env bash
# =============================================================================
# 07-monitoring.sh — ServiceMonitor · Liveness/Readiness Probes · Resource Limits
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/demo-config.sh"

header "ACT 3 — Monitoring, Health Probes & Resource Limits"

check_login
use_project

# ─────────────────────────────────────────────────────────────────────────────
# PART 1 — ServiceMonitor: plug our app into Prometheus
# ─────────────────────────────────────────────────────────────────────────────
header "PART 1 — ServiceMonitor: scraping our app's /q/metrics"

step "Our app already exposes Prometheus metrics at /q/metrics (Micrometer):"
echo ""
ROUTE_URL=$(oc get route "${APP_NAME}" -n "${DEMO_PROJECT}" -o jsonpath='{.spec.host}' 2>/dev/null || \
            oc get route "${APP_NAME_V2}" -n "${DEMO_PROJECT}" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

if [[ -n "${ROUTE_URL}" ]]; then
  echo -e "  ${CYAN}http://${ROUTE_URL}/q/metrics${RESET}"
  echo ""
  echo "  Sample output (first 8 lines):"
  curl -sf "http://${ROUTE_URL}/q/metrics" 2>/dev/null | head -8 | sed 's/^/    /' || \
    echo "    (route not yet reachable — verify the app is deployed)"
fi
echo ""
pause

# ── Enable user workload monitoring in the cluster (idempotent) ──────────────
step "Enabling user-workload monitoring (cluster-wide config — needs cluster-admin):"
echo ""
cat <<'YAML'
  # ConfigMap: openshift-monitoring / cluster-monitoring-config
  data:
    config.yaml: |
      enableUserWorkload: true
YAML
echo ""

oc get cm cluster-monitoring-config -n openshift-monitoring &>/dev/null && \
  oc patch cm cluster-monitoring-config -n openshift-monitoring \
     --type=merge \
     -p '{"data":{"config.yaml":"enableUserWorkload: true\n"}}' 2>/dev/null && \
  ok "cluster-monitoring-config patched" || \
  warn "Could not patch cluster-monitoring-config (non-admin or already set — OK for demo)"
echo ""
pause

# ── Apply ServiceMonitor ──────────────────────────────────────────────────────
step "Applying ServiceMonitor — tells Prometheus WHERE to scrape our app:"
show_cmd "apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: ${APP_NAME}
  labels:
    app: ${APP_NAME}
spec:
  selector:
    matchLabels:
      app: ${APP_NAME}
  endpoints:
    - port: 8080-tcp
      path: /q/metrics
      interval: 15s"

oc apply -n "${DEMO_PROJECT}" -f - <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: ${APP_NAME}
  labels:
    app: ${APP_NAME}
spec:
  selector:
    matchLabels:
      app: ${APP_NAME}
  endpoints:
    - port: 8080-tcp
      path: /q/metrics
      interval: 15s
EOF

echo ""
ok "ServiceMonitor '${APP_NAME}' created"
echo ""
echo -e "  ${YELLOW}→ Console: Observe → Targets — our app will appear within ~30 s${RESET}"
echo ""
pause

# ── Show the ServiceMonitor object ───────────────────────────────────────────
step "Verify ServiceMonitor:"
oc get servicemonitor -n "${DEMO_PROJECT}"
echo ""
pause

# ─────────────────────────────────────────────────────────────────────────────
# PART 2 — Liveness & Readiness Probes
# ─────────────────────────────────────────────────────────────────────────────
header "PART 2 — Liveness & Readiness Probes"

cat <<'MSG'
  Kubernetes uses two probes to manage pod lifecycle:

  ┌──────────────────┬──────────────────────────────────────────────────────┐
  │ Probe            │ What happens when it FAILS                           │
  ├──────────────────┼──────────────────────────────────────────────────────┤
  │ Readiness        │ Pod removed from Service endpoints — no traffic sent │
  │ Liveness         │ Pod is KILLED and restarted by kubelet                │
  └──────────────────┴──────────────────────────────────────────────────────┘

  Our Quarkus app exposes:
    /q/health/live  → liveness  (is the JVM alive?)
    /q/health/ready → readiness (is the app ready to serve traffic?)
MSG
echo ""
pause

# ── Show current probe state ──────────────────────────────────────────────────
step "Current probe configuration on deployment/${APP_NAME}:"
echo ""
oc get deployment "${APP_NAME}" -n "${DEMO_PROJECT}" \
  -o jsonpath='{.spec.template.spec.containers[0].livenessProbe}' 2>/dev/null | \
  python3 -m json.tool 2>/dev/null || echo "  (no liveness probe yet)"
echo ""
oc get deployment "${APP_NAME}" -n "${DEMO_PROJECT}" \
  -o jsonpath='{.spec.template.spec.containers[0].readinessProbe}' 2>/dev/null | \
  python3 -m json.tool 2>/dev/null || echo "  (no readiness probe yet)"
echo ""
pause

# ── Curl the health endpoints live ───────────────────────────────────────────
step "Live health endpoint responses:"
if [[ -n "${ROUTE_URL}" ]]; then
  echo ""
  echo -e "  ${CYAN}GET /q/health/live${RESET}"
  curl -sf "http://${ROUTE_URL}/q/health/live" 2>/dev/null | python3 -m json.tool 2>/dev/null | sed 's/^/    /' || \
    echo "    (not reachable)"
  echo ""
  echo -e "  ${CYAN}GET /q/health/ready${RESET}"
  curl -sf "http://${ROUTE_URL}/q/health/ready" 2>/dev/null | python3 -m json.tool 2>/dev/null | sed 's/^/    /' || \
    echo "    (not reachable)"
fi
echo ""
pause

# ── Patch probes onto the deployment ─────────────────────────────────────────
step "Patching liveness + readiness probes onto deployment/${APP_NAME}:"
show_cmd "oc set probe deployment/${APP_NAME} -n ${DEMO_PROJECT}
  --liveness  --get-url=http://:8080/q/health/live
              --initial-delay-seconds=10 --period-seconds=10
  --readiness --get-url=http://:8080/q/health/ready
              --initial-delay-seconds=5  --period-seconds=5"

oc patch deployment "${APP_NAME}" -n "${DEMO_PROJECT}" \
  --type=json \
  -p='[
    {
      "op": "replace",
      "path": "/spec/template/spec/containers/0/livenessProbe",
      "value": {
        "httpGet": {"path": "/q/health/live", "port": 8080},
        "initialDelaySeconds": 10,
        "periodSeconds": 10,
        "failureThreshold": 3
      }
    },
    {
      "op": "replace",
      "path": "/spec/template/spec/containers/0/readinessProbe",
      "value": {
        "httpGet": {"path": "/q/health/ready", "port": 8080},
        "initialDelaySeconds": 5,
        "periodSeconds": 5,
        "failureThreshold": 3
      }
    }
  ]'

echo ""
ok "Probes patched — rollout triggered"
wait_for_deployment "${APP_NAME}"
echo ""
pause

# ── Show probes in console ─────────────────────────────────────────────────────
step "Verify probes are configured:"
oc get deployment "${APP_NAME}" -n "${DEMO_PROJECT}" \
  -o jsonpath='{range .spec.template.spec.containers[*]}{.name}{"\n  liveness : "}{.livenessProbe.httpGet.path}{"\n  readiness: "}{.readinessProbe.httpGet.path}{"\n"}{end}'
echo ""
echo -e "  ${YELLOW}→ Console: Workloads → Deployments → ${APP_NAME} → YAML — scroll to livenessProbe${RESET}"
echo ""

# ── Show what a failing probe looks like (describe) ──────────────────────────
step "What a failing liveness probe looks like:"
cat <<'MSG'
  Events from a pod where liveness fails:

    Warning  Unhealthy  Liveness probe failed: HTTP probe failed with statuscode: 503
    Warning  Killing    Container demo-app failed liveness probe, will be restarted
    Normal   Pulled     Successfully pulled image ...
    Normal   Started    Started container demo-app

  → Kubernetes auto-restarts the container. RESTARTS counter increments.
  → Once RESTARTS > threshold → CrashLoopBackOff until the root cause is fixed.
MSG
echo ""
pause

# ─────────────────────────────────────────────────────────────────────────────
# PART 3 — Resource Requests & Limits
# ─────────────────────────────────────────────────────────────────────────────
header "PART 3 — Resource Requests & Limits"

cat <<'MSG'
  Every container should declare:

  ┌──────────────┬────────────────────────────────────────────────────────────┐
  │ Field        │ Meaning                                                    │
  ├──────────────┼────────────────────────────────────────────────────────────┤
  │ requests.cpu │ Guaranteed CPU — used by scheduler to place the pod        │
  │ requests.mem │ Guaranteed RAM — kubelet reserves this on the node         │
  │ limits.cpu   │ Hard cap — container is throttled if it exceeds this       │
  │ limits.mem   │ Hard cap — container is OOMKilled if it exceeds this       │
  └──────────────┴────────────────────────────────────────────────────────────┘

  Why it matters:
    • No requests → scheduler cannot make good placement decisions
    • No limits   → one noisy-neighbour pod can starve the whole node
    • requests = limits → Guaranteed QoS (best for production)
MSG
echo ""
pause

# ── Show current resource state ───────────────────────────────────────────────
step "Current resource configuration on deployment/${APP_NAME}:"
echo ""
oc get deployment "${APP_NAME}" -n "${DEMO_PROJECT}" \
  -o jsonpath='{.spec.template.spec.containers[0].resources}' 2>/dev/null | \
  python3 -m json.tool 2>/dev/null || echo "  (no resources set)"
echo ""
pause

# ── Apply resource requests + limits ─────────────────────────────────────────
step "Patching resource requests + limits onto deployment/${APP_NAME}:"
show_cmd "oc set resources deployment/${APP_NAME} -n ${DEMO_PROJECT}
  --requests=cpu=100m,memory=256Mi
  --limits=cpu=500m,memory=512Mi"

oc patch deployment "${APP_NAME}" -n "${DEMO_PROJECT}" \
  --type=json \
  -p='[
    {
      "op": "replace",
      "path": "/spec/template/spec/containers/0/resources",
      "value": {
        "requests": {"cpu": "100m", "memory": "256Mi"},
        "limits":   {"cpu": "500m", "memory": "512Mi"}
      }
    }
  ]'

echo ""
ok "Resource limits patched — rollout triggered"
wait_for_deployment "${APP_NAME}"
echo ""
pause

# ── Verify ────────────────────────────────────────────────────────────────────
step "Verify resource configuration:"
echo ""
oc get deployment "${APP_NAME}" -n "${DEMO_PROJECT}" \
  -o jsonpath='{range .spec.template.spec.containers[*]}{.name}{"\n  requests: cpu="}{.resources.requests.cpu}{"  memory="}{.resources.requests.memory}{"\n  limits  : cpu="}{.resources.limits.cpu}{"  memory="}{.resources.limits.memory}{"\n"}{end}'
echo ""

step "Actual pod resource usage (top):"
oc adm top pod -n "${DEMO_PROJECT}" -l "app=${APP_NAME}" 2>/dev/null || \
  warn "oc adm top not available (metrics-server may still be warming up)"
echo ""
echo -e "  ${YELLOW}→ Console: Observe → Dashboards → Kubernetes/Compute Resources/Namespace (Pods)${RESET}"
echo -e "  ${YELLOW}  Filter namespace: ${DEMO_PROJECT} — see request/limit bars per pod${RESET}"
echo ""
pause

# ── Show LimitRange / ResourceQuota if present ────────────────────────────────
step "Namespace-level guardrails (if configured by cluster admin):"
echo ""
echo -e "  ${CYAN}LimitRange — default requests/limits per container:${RESET}"
oc get limitrange -n "${DEMO_PROJECT}" 2>/dev/null || echo "  (none)"
echo ""
echo -e "  ${CYAN}ResourceQuota — total budget for the namespace:${RESET}"
oc get resourcequota -n "${DEMO_PROJECT}" 2>/dev/null || echo "  (none)"
echo ""
pause

# ─────────────────────────────────────────────────────────────────────────────
# RECAP
# ─────────────────────────────────────────────────────────────────────────────
header "RECAP — What we just did"

echo ""
echo -e "  ${BOLD}1. ServiceMonitor${RESET}"
echo -e "     • Registered our app with cluster Prometheus"
echo -e "     • Metrics visible at Observe → Targets + Observe → Metrics"
echo ""
echo -e "  ${BOLD}2. Liveness Probe${RESET}     → /q/health/live  (restart unhealthy container)"
echo -e "     ${BOLD}   Readiness Probe${RESET}    → /q/health/ready (remove from load-balancer when not ready)"
echo ""
echo -e "  ${BOLD}3. Resource Requests / Limits${RESET}"
echo -e "     • requests: cpu=100m  memory=256Mi  (scheduler guarantee)"
echo -e "     • limits  : cpu=500m  memory=512Mi  (hard cap / OOMKill)"
echo ""
echo -e "  ${YELLOW}All patched on a live deployment — zero downtime.${RESET}"
echo ""
ok "Monitoring demo complete — next: Scaling (08-scaling.sh)"
echo ""

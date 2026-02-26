#!/usr/bin/env bash
# =============================================================================
# 09-monitoring.sh — ServiceMonitor: plug our app into Prometheus
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/demo-config.sh"

header "ACT 3 — Monitoring: ServiceMonitor & Prometheus"

check_login
use_project

# ─────────────────────────────────────────────────────────────────────────────
# PART 1 — Verify the live metrics endpoint
# ─────────────────────────────────────────────────────────────────────────────
header "PART 1 — Our app already speaks Prometheus"

step "Our app exposes Micrometer metrics at /q/metrics (no code changes needed):"
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
cat <<'MSG'
  What Micrometer gives us for free:
    • JVM metrics      — heap, GC, threads
    • HTTP metrics     — request count, error rate, latency histograms
    • System metrics   — CPU usage, file descriptors

  → No instrumentation code required. The platform scrapes this.
MSG
echo ""
pause

# ─────────────────────────────────────────────────────────────────────────────
# PART 2 — Enable user workload monitoring (cluster-wide, once per cluster)
# ─────────────────────────────────────────────────────────────────────────────
header "PART 2 — Enable user-workload monitoring"

step "Enabling user-workload monitoring (cluster-admin required — idempotent):"
echo ""
cat <<'YAML'
  # ConfigMap: openshift-monitoring / cluster-monitoring-config
  data:
    config.yaml: |
      enableUserWorkload: true
YAML
echo ""
cat <<'MSG'
  Without this flag:  Prometheus only scrapes cluster components (nodes, etcd, …)
  With this flag:     User workloads are eligible to be scraped via ServiceMonitor
MSG
echo ""

oc get cm cluster-monitoring-config -n openshift-monitoring &>/dev/null && \
  oc patch cm cluster-monitoring-config -n openshift-monitoring \
     --type=merge \
     -p '{"data":{"config.yaml":"enableUserWorkload: true\n"}}' 2>/dev/null && \
  ok "cluster-monitoring-config patched" || \
  warn "Could not patch cluster-monitoring-config (non-admin or already set — OK for demo)"
echo ""
pause

# ─────────────────────────────────────────────────────────────────────────────
# PART 3 — Apply the ServiceMonitor
# ─────────────────────────────────────────────────────────────────────────────
header "PART 3 — Apply ServiceMonitor"

step "The ServiceMonitor CR tells Prometheus WHERE and HOW to scrape our app:"
show_cmd "apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: ${APP_NAME}
  labels:
    app: ${APP_NAME}
spec:
  selector:
    matchLabels:
      app: ${APP_NAME}      # ← must match the Service label
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
echo -e "  ${YELLOW}→ Console: Observe → Targets — our app endpoint appears within ~30 s${RESET}"
echo ""
pause

# ─────────────────────────────────────────────────────────────────────────────
# PART 4 — Verify and query
# ─────────────────────────────────────────────────────────────────────────────
header "PART 4 — Verify scraping + query metrics"

step "Verify ServiceMonitor object:"
oc get servicemonitor -n "${DEMO_PROJECT}"
echo ""
pause

step "Run a live PromQL query in the console:"
cat <<'MSG'
  Navigate to: Observe → Metrics

  Try these queries:
    http_server_requests_seconds_count{namespace="ocp-demo"}
    jvm_memory_used_bytes{namespace="ocp-demo"}
    process_cpu_usage{namespace="ocp-demo"}

  → Each metric is labelled with pod name — drill into individual instance behaviour.
MSG
echo ""
echo -e "  ${YELLOW}→ Console: Observe → Dashboards → Kubernetes/Compute Resources/Namespace (Pods)${RESET}"
echo ""
pause

# ─────────────────────────────────────────────────────────────────────────────
# RECAP
# ─────────────────────────────────────────────────────────────────────────────
header "RECAP — Monitoring"

echo ""
echo -e "  ${BOLD}1. App metrics endpoint${RESET}   /q/metrics  (Micrometer, Prometheus format, zero code)"
echo -e "  ${BOLD}2. Cluster flag${RESET}            enableUserWorkload: true  (once per cluster)"
echo -e "  ${BOLD}3. ServiceMonitor CR${RESET}       tells Prometheus: scrape THIS service at /q/metrics every 15 s"
echo -e "  ${BOLD}4. Console${RESET}                 Observe → Targets / Metrics / Dashboards"
echo ""
ok "Monitoring demo complete — next: Scaling (10-scaling.sh)"
echo ""

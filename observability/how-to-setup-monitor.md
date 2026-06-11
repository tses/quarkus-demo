# How to set up Connectivity Link monitoring

Ref: Red Hat Connectivity Link 1.3 - Observability.
Conceptual walkthrough (how it works / demo talk-track): [`demo/18-connectivity-observability.md`](../demo/18-connectivity-observability.md).
Namespaces here: `kuadrant-system` (CL), `monitoring` (Grafana), `openshift-ingress` (gateway/istiod).

## Prereqs
```bash
# user workload monitoring must be on -> expect: enableUserWorkload: true
oc get cm cluster-monitoring-config -n openshift-monitoring -o jsonpath='{.data.config\.yaml}' | grep enableUserWorkload
```
Connectivity Link (Kuadrant) + Grafana operator installed.

## 1. Metrics + monitors
This cluster uses the OpenShift Gateway API: istiod runs in `openshift-ingress`, not `gateway-system`.
The `kustomization.yaml` in this folder pulls the upstream base and retargets the istiod `ServiceMonitor` + `Telemetry` to `openshift-ingress`.
```bash
oc apply -k .
```

## 2. Enable observability
```bash
oc -n kuadrant-system patch kuadrant kuadrant --type merge \
  -p '{"spec":{"observability":{"enable":true}}}'
# verify auto-created monitors
oc get servicemonitor,podmonitor -A -l kuadrant.io/observability=true
```

## 3. Grafana datasource - durable token
Grafana SA queries Thanos with a non-expiring SA token (a hardcoded `oc whoami -t` expires -> 401).
```bash
# RBAC
oc adm policy add-cluster-role-to-user cluster-monitoring-view -z grafana-sa -n monitoring

# long-lived token secret (controller fills .data.token)
oc apply -f - <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: grafana-sa-thanos-token
  namespace: monitoring
  annotations:
    kubernetes.io/service-account.name: grafana-sa
type: kubernetes.io/service-account-token
EOF

# datasource reads token from secret (no hardcoded token)
oc -n monitoring patch grafanadatasource thanos-query-ds --type merge -p '{
  "spec":{
    "datasource":{"secureJsonData":{"httpHeaderValue1":"Bearer ${token}"}},
    "valuesFrom":[{"targetPath":"secureJsonData.httpHeaderValue1",
      "valueFrom":{"secretKeyRef":{"name":"grafana-sa-thanos-token","key":"token"}}}]
  }
}'
```

## Verify
```bash
# datasource -> expect: ApplySuccessful
oc -n monitoring get grafanadatasource thanos-query-ds -o jsonpath='{.status.conditions[*].reason}{"\n"}'

# token -> Thanos -> expect: 200
HOST=$(oc -n openshift-monitoring get route thanos-querier -o jsonpath='https://{.status.ingress[0].host}')
SA_TOKEN=$(oc -n monitoring get secret grafana-sa-thanos-token -o jsonpath='{.data.token}' | base64 -d)
curl -sk -o /dev/null -w "%{http_code}\n" -H "Authorization: Bearer $SA_TOKEN" \
  --data-urlencode 'query=up' "$HOST/api/v1/query"
```

## Notes
- Dashboards: platform-engineer / app-developer / business-user.
- business-user (requests/sec per API) needs gateway traffic; `istio_requests_total` stays empty until requests flow through the gateway.
- Per-app panels (app-developer / business-user) join Istio metrics with Gateway API state metrics **only** when each `HTTPRoute` carries `service` and `deployment` labels matching the backend (e.g. `service=ocp-demo-app`, `deployment=ocp-demo-app`). `scripts/18-connectivity-observability.sh` applies these labels before sending traffic.
- Do not hardcode `oc whoami -t` in the datasource - it expires and breaks Grafana with 401.

# ACT 4 — Advanced Authorization with External Metadata

> **Script:** `scripts/17-external-metadata.sh` _(not built yet — md first, for discussion)_
> **Overview:** Steps 15–16 protected the API on **one** route with **static** rules: a valid API key (*who*) and a fixed quota (*how often*). This step demonstrates **dynamic, runtime authorization** on a **separate FQDN** (`ocp-demo-app-mtls.api.<domain>`, same Gateway and backend): client identity arrives in an HTTP header (set upstream by a WAF doing mTLS), Authorino fetches the caller's **tier live from an external metadata service**, and a `RateLimitPolicy` applies a **per-tier quota**.

> **Real-world framing:** In production, **mTLS happens at the WAF/edge**, not at this Gateway. The WAF authenticates the client certificate and forwards the verified client identity as a trusted header (here `X-Client-Id`). This route therefore performs **no authentication of its own** (`anonymous`) — it *trusts* the upstream header and makes its decision from external metadata keyed on that identity.

---

## Scenario

Two known clients, each mapped to a tier with its own quota; unknown clients are rejected outright:

| `X-Client-Id` | Tier (from metadata-svc) | Quota | Result |
|---|---|---|---|
| `user1` | `gold` | 5 requests / 10s | `200` until limit, then `429` |
| `user2` | `silver` | 2 requests / 10s | `200` until limit, then `429` |
| anything else | `deny` | — | `403` (authorization) |

> **Key point:** The tier is **not** in the policy — it is fetched **live** from `metadata-svc` on every request. Change what the service returns for a client and the behaviour changes immediately, with no policy edit and no redeploy.

---

## Mental Model

**The Authorino request pipeline (phases run in order):**

| Phase | What it does on this route |
|---|---|
| `authentication` | `anonymous` — no credential check (WAF already did mTLS upstream) |
| `metadata` | **Fetch the caller's tier** from `metadata-svc`, passing `X-Client-Id` |
| `authorization` | Deny if the returned tier is `deny` (unknown client) |
| `response` | **Export** the resolved `tier` + `userid` as dynamic metadata for the rate-limit phase |

Then, **separately**, the `RateLimitPolicy` on the same route reads the exported values (`auth.identity.*`) and applies the matching per-tier quota via Limitador.

| Resource | Owner | Responsibility |
|---|---|---|
| `HTTPRoute` `ocp-demo-app-mtls` | App / Platform | New host; same backend `Service` |
| `AuthPolicy` (anonymous + metadata) | Security | Fetch tier from metadata-svc; reject unknown clients |
| `RateLimitPolicy` (per tier) | Security / Platform | `gold 5/10s`, `silver 2/10s`, counted **per client id** |
| **`metadata-svc`** | App / Platform | Returns `{"tier": …, "id": …}` for a given `X-Client-Id` |
| Authorino / Limitador | Platform (Kuadrant) | Run the pipeline and enforce the quota |

---

## How It Fits Together

![Metadata Service flow — Client request with X-Client-Id → Gateway → Authorino (anonymous auth, metadata lookup, authorization) → Metadata Service returns tier+id; allow → Limitador quota check (gold 5/10s, silver 2/10s) → Backend, deny → 403, over-limit → 429](img/ChatGPT%20Image%20Jun%2011,%202026,%2002_48_49%20PM.png)

---

## Steps 

### 1. Confirm Prerequisites

```bash
oc get crd authpolicies.kuadrant.io ratelimitpolicies.kuadrant.io
oc get gateway demo-gateway -n ocp-demo \
  -o jsonpath='{range .spec.listeners[*]}{.name}: {.hostname}{"\n"}{end}'
# https: *.api.<domain>   ← wildcard covers the new FQDN
```

---

### 2. Deploy the External Metadata Service

A tiny in-cluster HTTP stub (Python stdlib, no build, no registry) that reads the forwarded `X-Client-Id` header and returns that client's tier:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: metadata-svc
  namespace: ocp-demo
  labels: { app: metadata-svc }
spec:
  replicas: 1
  selector: { matchLabels: { app: metadata-svc } }
  template:
    metadata: { labels: { app: metadata-svc } }
    spec:
      containers:
        - name: svc
          image: registry.access.redhat.com/ubi9/python-312:latest
          ports: [{ containerPort: 8080 }]
          command: ["python", "-c"]
          args:
            - |
              import json
              from http.server import BaseHTTPRequestHandler, HTTPServer
              TIERS = {"user1": "gold", "user2": "silver"}   # the live "source of truth"
              class H(BaseHTTPRequestHandler):
                  def do_GET(self):
                      client = self.headers.get("X-Client-Id", "")
                      tier = TIERS.get(client, "deny")
                      # Return the resolved identity too, so policies count on what
                      # the metadata service validated — not the raw client header.
                      cid = client if tier != "deny" else ""
                      body = json.dumps({"tier": tier, "id": cid}).encode()
                      self.send_response(200)
                      self.send_header("Content-Type", "application/json")
                      self.send_header("Content-Length", str(len(body)))
                      self.end_headers()
                      self.wfile.write(body)
                  def log_message(self, *a): pass
              HTTPServer(("0.0.0.0", 8080), H).serve_forever()
---
apiVersion: v1
kind: Service
metadata:
  name: metadata-svc
  namespace: ocp-demo
spec:
  selector: { app: metadata-svc }
  ports: [{ port: 8080, targetPort: 8080 }]
```

> **Tip:** The tier map is in-code for clarity. To flip a client's tier live on stage, swap it for a ConfigMap/env-driven lookup so a `oc set env` / `oc edit cm` changes the answer without a rebuild.

---

### 3. Add the Second HTTPRoute (new FQDN, same backend)

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: ocp-demo-app-mtls
  namespace: ocp-demo
spec:
  parentRefs:
    - name: demo-gateway
  hostnames:
    - "ocp-demo-app-mtls.api.<domain>"     # covered by the wildcard listener
  rules:
    - backendRefs:
        - name: ocp-demo-app               # SAME service as the step-13 route
          port: 8080
```

---

### 4. AuthPolicy — anonymous + external metadata

```yaml
apiVersion: kuadrant.io/v1
kind: AuthPolicy
metadata:
  name: demo-app-mtls-auth
  namespace: ocp-demo
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: ocp-demo-app-mtls
  rules:
    authentication:
      "anonymous":
        anonymous: {}                       # WAF already did mTLS upstream
    metadata:
      "caller_info":
        http:
          url: "http://metadata-svc.ocp-demo.svc.cluster.local:8080/lookup"
          method: GET
          headers:
            "X-Client-Id":
              selector: "request.headers.x-client-id"   # forward the WAF header
    authorization:
      "known-clients-only":
        patternMatching:
          patterns:
            - selector: 'auth.metadata.caller_info.tier'
              operator: neq
              value: deny                   # unknown client → 403
    response:
      success:
        filters:
          "identity":                       # exported as auth.identity.* downstream
            json:
              properties:
                "tier":
                  selector: auth.metadata.caller_info.tier
                "userid":
                  selector: auth.metadata.caller_info.id
```

> **Note:** The metadata entry is named `caller_info` (underscore) because it is referenced from **CEL** expressions, where a hyphen would be parsed as subtraction.

> **Key point — the auth→rate-limit bridge:** The rate-limit phase **cannot** read `auth.metadata.*` (that data is internal to the auth phase). The `response.success.filters` block **exports** the resolved `tier` and `userid` as Envoy dynamic metadata, which the `RateLimitPolicy` then reads as **`auth.identity.tier`** / **`auth.identity.userid`** (the filter is named `identity`).

---

### 5. RateLimitPolicy — per-tier, per-client quota

```yaml
apiVersion: kuadrant.io/v1
kind: RateLimitPolicy
metadata:
  name: demo-app-mtls-rl
  namespace: ocp-demo
spec:
  targetRef:
    group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: ocp-demo-app-mtls
  limits:
    "gold":
      rates:
        - limit: 5
          window: 10s
      when:
        - predicate: 'auth.identity.tier == "gold"'
      counters:
        - expression: 'auth.identity.userid'
    "silver":
      rates:
        - limit: 2
          window: 10s
      when:
        - predicate: 'auth.identity.tier == "silver"'
      counters:
        - expression: 'auth.identity.userid'
```

> **Key point:** `counters` keeps a **separate budget per client id**, using the `userid` **exported by the AuthPolicy** (the identity the metadata service validated, not the raw request header) — so each client gets an independent quota. `when` selects which limit applies based on the **tier the AuthPolicy exported** (`auth.identity.tier`) — the two policies cooperate on the same route.

---

### 6. Wait for Both Policies to be Enforced

```bash
oc wait authpolicy/demo-app-mtls-auth   -n ocp-demo --for=condition=Enforced --timeout=60s
oc wait ratelimitpolicy/demo-app-mtls-rl -n ocp-demo --for=condition=Enforced --timeout=60s
```

---

### 7. Demonstrate — Tier-Based Behaviour, No Credentials

Identity is just a header; no API key on this route:

```bash
GW=<gateway-address>; H=ocp-demo-app-mtls.api.<domain>

# user1 → gold → 5 allowed, then 429
for i in $(seq 1 7); do
  curl -sk -o /dev/null -w '%{http_code} ' --resolve "$H:443:$GW" \
    -H 'X-Client-Id: user1' "https://$H/api/info"
done; echo
# 200 200 200 200 200 429 429

# user2 → silver → only 2 allowed
for i in $(seq 1 7); do
  curl -sk -o /dev/null -w '%{http_code} ' --resolve "$H:443:$GW" \
    -H 'X-Client-Id: user2' "https://$H/api/info"
done; echo
# 200 200 429 429 429 429 429

# unknown client → rejected at authorization
curl -sk -o /dev/null -w '%{http_code}\n' --resolve "$H:443:$GW" \
  -H 'X-Client-Id: ghost' "https://$H/api/info"
# 403
```

> **Security note:** Because the route trusts `X-Client-Id` blindly, in production **only the WAF may set it** — the edge must strip any client-supplied `X-Client-Id` and re-inject the value it derived from mTLS, so callers cannot spoof their identity.

---

## Recap

| Concept | Takeaway |
|---|---|
| Separate route + FQDN | Two auth strategies coexist under one Gateway by targeting different `HTTPRoute`s |
| Anonymous auth | This route trusts an upstream WAF (mTLS); identity arrives as a header |
| External metadata | Authorino fetches the caller's tier live from `metadata-svc` per request |
| Auth→rate-limit bridge | `AuthPolicy` exports `tier`/`userid` via `response.success.filters`; the `RateLimitPolicy` reads them as `auth.identity.*` |
| Per-tier rate limit | `RateLimitPolicy` applies `gold 5/10s` vs `silver 2/10s` based on the exported tier |
| `counters` per client | Each client id gets an independent budget — no shared quota |
| Runtime decisions | Change the metadata → behaviour changes with no policy edit or redeploy |

> **Tip:** Steps 15–16 answered *who* and *how often* with static rules on one host. This step shows **context-aware, identity-driven** policy on a second host — authorization and quotas computed live from an external source. Next we **observe** all of this protected traffic end-to-end.

---

## ⬅️ Previous: [Protect API with RateLimitPolicy](16-rate-limit-policy.md) | ➡️ Next: [Observe API Connectivity](18-connectivity-observability.md)

# OCP Demo App

A purposely-rich Quarkus REST API built for the OpenShift intro training demo.

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/info` | App identity: **hostname (= pod name)**, version, colour label |
| GET | `/api/burn?seconds=30` | 🔥 CPU stress — saturates all cores for N seconds → triggers HPA |
| GET | `/q/health` | Combined health (liveness + readiness) |
| GET | `/q/health/live` | Liveness probe |
| GET | `/q/health/ready` | Readiness probe |
| GET | `/q/metrics` | Prometheus metrics |
| GET | `/swagger-ui` | Swagger UI |

## Demo usage

### Show hostname (which pod is serving)
```bash
# Run several times — after scaling you'll see different pod names
curl http://<ROUTE>/api/info | jq .
```

### Trigger CPU burn for HPA demo
```bash
# Fire in background — watch `oc get hpa -w` and `oc top pods`
curl "http://<ROUTE>/api/burn?seconds=60" &
watch oc get pods -n ocp-demo
```

## Local development

```bash
# Start in dev mode (hot reload)
./mvnw compile quarkus:dev

# Run tests
./mvnw test

# Package
./mvnw package
```

## Environment variables (OpenShift ConfigMap / Secret)

| Variable | Default | Description |
|----------|---------|-------------|
| `APP_VERSION` | `1.0.0` | Shown in `/api/info` |
| `APP_COLOUR` | `blue` | Shown in `/api/info` — set to `green` for v2 |

## Traffic splitting demo

Deploy a second instance (`quarkus-hello-v2`) with `APP_COLOUR=green`.
The `/api/info` response will clearly show `"colour": "green"` and a
**different hostname** — making the traffic split visually obvious.

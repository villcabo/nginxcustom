# OpenResty API Gateway

A file-driven API gateway on **OpenResty 1.31.1.1** (nginx core 1.31.1 + LuaJIT). You describe routes, upstreams and health checks in plain files; the gateway hot-reloads them, discovers backends through DNS, probes them actively and drops dead peers before a request ever reaches them — the Traefik experience, without a control plane or a database.

- Base: `openresty/openresty:1.31.1.1-bookworm-fat`
- Runs as the non-root `nginx` user (uid 101)
- Ports: `8080` traffic, `8081` internal status and metrics (never publish it)
- Bundled: Brotli (filter + static), `lua-resty-upstream-healthcheck`, `nginx-lua-prometheus`, headers-more

## How it is laid out

| Path | Owner | Purpose |
|------|-------|---------|
| `/usr/local/openresty/nginx/conf/nginx.conf` | image | Gateway defaults. Do not mount over it. |
| `/etc/nginx/conf.d/*.conf` | **you** | Upstreams, servers, extra rate-limit zones. Loaded inside `http {}`. |
| `/etc/nginx/conf.d/healthchecks.json` | **you** | Active health checks per upstream. |
| `/usr/local/openresty/nginx/conf/snippets/` | image | `proxy-headers.conf`, `json-errors.conf`. |
| `/usr/local/openresty/nginx/conf/examples/` | image | Copy-paste starting point. |
| `/var/log/nginx/` | runtime | `access.log` (JSON lines) and `error.log`, rotated in-process. |

Mount your own `conf.d` and that is the whole configuration surface:

```bash
docker run -d -p 8080:8080 \
  -v "$PWD/conf.d:/etc/nginx/conf.d:ro" \
  -v "$PWD/logs:/var/log/nginx" \
  villcabo/openresty-apigateway:1.31.1.1-bookworm-fat
```

Without a mount, the image answers every request with a JSON 404.

## Routes and upstreams

Plain nginx, so everything you know still applies. Two kinds of pool:

```nginx
# Static pool: fixed peers.
upstream orders_api {
    zone orders_api 64k;
    server orders-1:8080 max_fails=2 fail_timeout=10s;
    server orders-2:8080 max_fails=2 fail_timeout=10s;
    keepalive 32;
}

# Dynamic pool: peers follow the DNS record at runtime. Scale the service and the
# gateway picks up new replicas (and drops removed ones) with no reload.
upstream users_api {
    zone users_api 64k;
    server tasks.users:8080 resolve max_fails=2 fail_timeout=10s;
    keepalive 32;
}

server {
    listen 8080;
    server_name api.example.com;
    include snippets/json-errors.conf;

    location /orders/ {
        limit_req zone=per_ip burst=100 nodelay;
        proxy_pass http://orders_api/;
    }

    location /users/ {
        proxy_pass http://users_api/;
    }
}
```

For dynamic pools use `tasks.<service>` on Docker Swarm, the service name on Compose, or a headless Service on Kubernetes. `resolve` needs a `zone`; the resolver is taken from `/etc/resolv.conf` unless `GATEWAY_RESOLVER` is set, and records are re-read every `GATEWAY_RESOLVER_VALID`.

See `examples/api.conf` for WebSockets, per-API-key rate limits and opting non-idempotent routes into retries.

## Active health checks

Declare them per upstream in `conf.d/healthchecks.json` — no Lua to write:

```json
{
  "defaults": { "path": "/health", "interval": 2000, "timeout": 1000, "fall": 2, "rise": 2, "valid_statuses": [200, 204] },
  "upstreams": {
    "orders_api": { "path": "/actuator/health", "host": "orders.internal" },
    "users_api": {}
  }
}
```

- `path` and `host` build the probe request (`host` defaults to the upstream name); `http_req` overrides it entirely.
- Any other `spawn_checker` option (`concurrency`, `type`, …) is passed through.
- Works on dynamic pools too: new peers found through DNS are probed as soon as they appear.
- A peer goes DOWN after `fall` failed probes and returns after `rise` successes. Between probes, `max_fails` and `proxy_next_upstream` retry the request on another peer, so a peer dying mid-interval is invisible to idempotent requests.

## Hot reload

Every `GATEWAY_WATCH_INTERVAL` seconds the gateway fingerprints `conf.d`. On a change it runs `openresty -t` first: a valid config is reloaded gracefully, an invalid one is logged and **the running config keeps serving**. Symlinked files (Kubernetes ConfigMaps) are followed.

## Defaults the gateway applies

- `server_tokens off` and no `Server` header; `X-Content-Type-Options: nosniff`.
- `X-Request-ID`: kept from the caller or generated, forwarded upstream and returned to the client.
- Proxy: HTTP/1.1 with upstream keepalive, WebSocket-aware `Connection`, standard `X-Forwarded-*` headers. A location that declares its own `proxy_set_header` loses the inherited ones — add `include snippets/proxy-headers.conf;` there.
- Timeouts: connect 5s, send/read 60s. Retries on `error timeout 502 503 504`, up to 3 tries within 15s, never for non-idempotent methods unless the route opts in.
- Gzip and Brotli for JSON/text above 1 KB (skipped when the upstream already encoded).
- Rate limiting: zones `per_ip` (50 r/s) and `conn_per_ip` ready to use per location; rejections return 429.
- Errors produced by the gateway itself (no route, 413, 429, 502/503/504) return JSON with the request id when the server includes `snippets/json-errors.conf`:
  `{"error":"too_many_requests","status":429,"request_id":"…"}`. Upstream error bodies pass through untouched.

The gateway owns the `init_worker_by_lua*` and `log_by_lua*` phases at `http` level — do not declare them in `conf.d`.

## Status and metrics (port 8081)

| Endpoint | Content |
|----------|---------|
| `/healthz` | Liveness, used by the image `HEALTHCHECK`. |
| `/status/upstreams` | Every peer with UP/DOWN as seen by the health checker. |
| `/metrics` | Prometheus: `gateway_http_requests_total`, `gateway_http_request_duration_seconds`, `gateway_upstream_response_duration_seconds`, `gateway_connections`, `nginx_upstream_status_info`. |
| `/nginx_status` | `stub_status`. |

Metric labels are the `server_name` and upstream name, never the client's `Host` or URI, so cardinality stays bounded.

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `LOGROTATE_FREQUENCY` | `daily` | `hourly`, `daily`, `weekly`, `monthly` — rotate on that schedule — or `size` to rotate only by size. |
| `LOGROTATE_MAXSIZE` | `1G` | With a schedule: also rotate early when a file exceeds it (empty disables). With `size`: the only trigger. Accepts `k`/`M`/`G`. |
| `LOGROTATE_ROTATE` | `30` | Rotated files to keep per log. |
| `LOGROTATE_COMPRESS` | `true` | Gzip rotated files (the newest one stays uncompressed one cycle). |
| `LOGROTATE_DELAY_SECONDS` | `300` | How often logrotate checks whether a rotation is due. Keep it well below the smallest trigger. |
| `LOGROTATE_STATE_FILE` | `/var/log/nginx/.logrotate.status` | Rotation state; lives with the logs so schedules survive restarts. |
| `GATEWAY_WATCH_CONFIG` | `true` | Hot-reload `conf.d` on change. |
| `GATEWAY_WATCH_INTERVAL` | `5` | Seconds between config checks. |
| `GATEWAY_RESOLVER` | from `/etc/resolv.conf` | DNS server for `resolve` upstreams. |
| `GATEWAY_RESOLVER_VALID` | `10s` | How long a DNS answer is trusted. |
| `GATEWAY_REAL_IP_FROM` | — | Comma-separated CIDRs of trusted proxies/load balancers; enables real client IPs from `X-Forwarded-For`. |
| `GATEWAY_CLIENT_MAX_BODY_SIZE` | `10m` | Default request body limit (override per server/location). |

Invalid values stop the container at startup with a clear error instead of running with a broken config.

## Version coupling

The OpenResty tag is `<nginx-core>.<resty-revision>`. Brotli is compiled against the vanilla nginx source given by `ARG NGINX_CORE_VERSION` — bump it together with the `FROM` tag or the module will not load.

## Testing

`../test-apigateway/` runs the gateway with a static pool and a DNS-discovered pool, and `test-failover.sh` probes it while you stop, start and scale backends.

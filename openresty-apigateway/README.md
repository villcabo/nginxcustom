# OpenResty API Gateway

A file-driven API gateway on **OpenResty 1.31.1.1** (nginx core 1.31.1 + LuaJIT). You describe routes, upstreams and health checks in plain files. The gateway validates them, hot-reloads them, keeps serving the last good version when you break them, discovers backends through DNS and probes them actively, so dead peers are dropped before a request reaches them. It gives you the Traefik experience without a control plane or a database.

- Image: `villcabo/openresty-apigateway:1.31.1.1-bookworm-fat`
- Runs as the non-root `nginx` user (uid 101). The nginx prefix, modules and Lua code are root-owned and read-only at runtime.
- Ports: `80`/`443` for traffic (non-root, see [Ports](#ports)). `8081` is for internal status and metrics; never publish it.
- Bundled: Brotli, `lua-resty-upstream-healthcheck`, `nginx-lua-prometheus`, headers-more.

## When to use it (and when not)

Use it as the single entry point in front of HTTP microservices when you want:
- active health checks;
- DNS-based discovery (Compose, Swarm, Kubernetes);
- rate limiting;
- consistent JSON errors, request ids and Prometheus metrics;
- everything configured with files you can review in a pull request.

It is **not** an identity provider and does not validate JWTs or API keys out of the box (see [Extending](#extending)). If you only need a static site or a plain reverse proxy, `nginx-logrotate` is lighter. Plain nginx is not enough for a gateway, because active health checks are an NGINX Plus feature: open-source nginx only notices a dead backend when a client request fails on it.

## Quick start

```
gateway/
├── docker-compose.yml
└── conf.d/
    ├── api.conf
    └── healthchecks.json
```

`conf.d/api.conf`:

```nginx
upstream orders_api {
    zone orders_api 64k;
    server orders:8080 resolve max_fails=2 fail_timeout=10s;
    keepalive 32;
}

server {
    listen 80;
    server_name api.example.com;
    include snippets/json-errors.conf;

    location /orders/ {
        limit_req zone=per_ip burst=100 nodelay;
        proxy_pass http://orders_api/;
    }
}
```

`conf.d/healthchecks.json`:

```json
{ "upstreams": { "orders_api": { "path": "/actuator/health", "host": "orders" } } }
```

`docker-compose.yml`:

```yaml
services:
  gateway:
    image: villcabo/openresty-apigateway:1.31.1.1-bookworm-fat
    container_name: gateway
    stop_grace_period: 35s
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "127.0.0.1:8081:8081"
    volumes:
      - ./conf.d:/etc/nginx/conf.d:ro
      - ./logs:/var/log/nginx
    environment:
      LOGROTATE_FREQUENCY: daily
      LOGROTATE_MAXSIZE: 500M
```

Without a mount, the image answers every request with a JSON 404.

## Ports

The gateway listens on the standard `80` and `443` inside the container while still running as the non-root `nginx` user. That works because Docker sets `net.ipv4.ip_unprivileged_port_start=0` in every container's network namespace. You decide what to expose on the host with `ports:` (`"8080:80"`, `"80:80"`, or nothing behind a load balancer).

Two environments do not get that sysctl:
- **`--network host`**: the host's own setting applies and binding fails with `bind() to 0.0.0.0:80 failed (13: Permission denied)`. Use the default bridge or overlay network, or `listen` on a port of 1024 or higher in your `conf.d`.
- **Kubernetes**: declare it in the pod spec (it is a "safe" sysctl since 1.22):

  ```yaml
  securityContext:
    sysctls:
      - name: net.ipv4.ip_unprivileged_port_start
        value: "0"
  ```

The ports are yours to choose: they are the `listen` directives in your `conf.d`. The image only uses 80/443 for its catch-all server, and `8081` for status.

## How configuration is loaded

| Path | Owner | Purpose |
|------|-------|---------|
| `/etc/nginx/conf.d/*.conf` | **you** | Upstreams, servers, extra rate-limit zones and maps. Loaded inside `http {}`. |
| `/etc/nginx/conf.d/healthchecks.json` | **you** | Active health checks per upstream. |
| `/usr/local/openresty/nginx/conf/nginx.conf` | image | Gateway defaults. Do not mount over it. |
| `/usr/local/openresty/nginx/conf/snippets/` | image | `proxy-headers.conf`, `json-errors.conf`. Include them as `snippets/<file>`. |
| `/usr/local/openresty/nginx/conf/examples/` | image | Annotated `api.conf` and `healthchecks.json` to start from. |
| `/var/log/nginx/` | runtime | `access.log` (JSON lines) and `error.log`, rotated in-process. |

Your files are never loaded directly. On startup and on every change, the gateway goes through these steps:

1. **Copy** `conf.d` to a candidate directory. Symlinks are followed, so Kubernetes ConfigMaps work.
2. **Validate** the candidate:
   - with `openresty -t`, inside a shadow copy of the real configuration;
   - by checking `healthchecks.json`: JSON syntax, known options and value types, and that every upstream it names is declared in a `.conf`.
   - by checking that every upstream `server` with a hostname uses `resolve` (see [Upstreams](#upstreams-always-use-resolve)).
3. **Publish** it as a snapshot (an atomic symlink swap to `conf/routes/`) and reload gracefully.

If validation fails, nothing is published: **the gateway keeps serving the last known-good snapshot**, logs the exact error and reports `fallback`. That also holds across `docker restart`: a container restarted with a broken `conf.d` starts on its previous snapshot instead of crash-looping. A brand-new container has no snapshot, so it refuses to start with an invalid config. Your CI or orchestrator should catch that before rollout.

Check the state at any time:

```bash
curl -s localhost:8081/status/config
# {"state":"valid","message":"published and reloaded","checked_at":1791369983,"snapshot":"..."}
```

To reference your own extra files from a `.conf`, keep them in `conf.d` and include them as `routes/<file>`, for example `include routes/cors.inc;`. Do not use the `/etc/nginx/conf.d/...` absolute path, which bypasses the snapshot.

## Upstreams: always use `resolve`

```nginx
upstream users_api {
    zone users_api 64k;
    server users:8080 resolve max_fails=2 fail_timeout=10s max_conns=200;
    keepalive 32;
}
```

- With `resolve`, the name is re-read every `GATEWAY_RESOLVER_VALID` (10s). Scaling a service up or down changes the pool with no reload, and backends that do not exist yet do not stop the gateway from starting.
- **Without** `resolve`, nginx resolves the name once at load time. One missing backend makes the gateway refuse to start or reload, and a recreated container with a new IP stays unreachable until the next reload.
- Service names: `<service>` on Compose, `tasks.<service>` on Swarm (one peer per replica), a headless Service on Kubernetes.
- `max_conns` works as a bulkhead: a slow backend cannot accumulate every connection of the gateway.

This is **enforced**: validation rejects any `server <hostname>` without `resolve`, with a message naming the file and upstream. IP literals, `localhost` and `unix:` sockets are exempt, because they never go through DNS.

## Active health checks

```json
{
  "defaults": { "path": "/health", "interval": 2000, "timeout": 1000, "fall": 2, "rise": 2 },
  "upstreams": {
    "orders_api": { "path": "/actuator/health", "host": "orders" },
    "billing_api": { "type": "https", "host": "billing.internal.example.com" }
  }
}
```

| Option | Default | Meaning |
|--------|---------|---------|
| `path` | `/health` | Probe path. **Must answer 200/204 on a healthy backend**, or every peer is marked DOWN and the route returns 502. |
| `host` | upstream name | `Host` header of the probe (and SNI for `https`). |
| `type` | `http` | `http` or `https`. |
| `ssl_verify` | `true` | Verify the backend certificate on `https` probes. |
| `port` | peer port | Probe a different port (e.g. a management port). |
| `interval` / `timeout` | `2000` / `1000` | Milliseconds between probes / per probe. |
| `fall` / `rise` | `2` / `2` | Consecutive failures to mark DOWN / successes to mark UP. |
| `valid_statuses` | `[200, 204]` | Status codes that count as healthy. |
| `concurrency` | `10` | Parallel probes per upstream. |
| `http_req` | built from `path`/`host` | Raw request, overrides `path` and `host`. |

Unknown options are rejected, so a typo like `"interva"` fails validation instead of being silently ignored. Peers discovered through DNS are probed as soon as they appear. Between probes, `max_fails` and `proxy_next_upstream` retry idempotent requests on another peer, so a peer dying mid-interval stays invisible to clients.

## What the gateway does for every request

- **Headers.**
  - No `Server` header; `X-Content-Type-Options: nosniff`.
  - `X-Request-ID` is kept when the caller sends a sane token (`[A-Za-z0-9._:-]`, at most 128 characters), otherwise generated. It is forwarded upstream and returned to the client.
- **Forwarded headers.**
  - In **edge mode** (no `GATEWAY_REAL_IP_FROM`), the client's `X-Forwarded-For` and `X-Forwarded-Proto` are discarded and replaced with what the gateway sees, so they cannot be spoofed.
  - **Behind a load balancer**, list its addresses in `GATEWAY_REAL_IP_FROM`. The real client IP is then recovered for logs and rate limits, and the forwarded chain is preserved.
- **Proxy defaults.**
  - HTTP/1.1 with upstream keepalive, and WebSockets work out of the box.
  - Timeouts: connect 5s, read/send 60s.
  - Retries go to another peer on `error timeout http_502 http_504`, at most 2 tries within 10s.
  - `503` is not retried, because retrying an overloaded pool multiplies its load. Non-idempotent methods are never retried unless a location opts in.
- **HTTPS upstreams** are verified against the system CA bundle (`proxy_ssl_verify on`). For a private CA, set `proxy_ssl_trusted_certificate` in the location.
- **Compression.** Gzip and Brotli for JSON/text above 1 KB.
- **Errors.** Errors produced by the gateway itself (no route, 413, 429, 502/503/504) return JSON when the server includes `snippets/json-errors.conf`. Upstream error bodies pass through untouched.

  ```json
  {"error":"too_many_requests","status":429,"request_id":"6f1c…"}
  ```

### Inheritance traps

- A location that sets **any** `proxy_set_header` loses the inherited ones. Add `include snippets/proxy-headers.conf;` in that location.
- The gateway owns `init_worker_by_lua*` and `log_by_lua*` at `http` level; do not declare them in `conf.d`.

## Rate limiting

Ready-made zones: `per_ip` (50 r/s) and `conn_per_ip`. Rejections return 429.

```nginx
location /api/ {
    limit_req  zone=per_ip burst=100 nodelay;
    limit_conn conn_per_ip 50;
    proxy_pass http://orders_api/;
}
```

Per API key, with a fallback to the client IP so a request without the header cannot skip the limit:

```nginx
map $http_x_api_key $api_limit_key {
    ""      $binary_remote_addr;
    default $http_x_api_key;
}
limit_req_zone $api_limit_key zone=per_api_key:10m rate=200r/s;
```

Behind a load balancer, **set `GATEWAY_REAL_IP_FROM`**. Otherwise every client shares the balancer's address and the per-IP limit becomes one global limit.

## Status and metrics (port 8081)

| Endpoint | Content |
|----------|---------|
| `/healthz` | Liveness, used by the image `HEALTHCHECK`. |
| `/status/config` | `valid` or `fallback`, the last message and the published snapshot. |
| `/status/upstreams` | Every peer with UP/DOWN as seen by the health checker. |
| `/metrics` | Prometheus metrics (below). |
| `/nginx_status` | `stub_status`. |

Access is restricted to `GATEWAY_STATUS_ALLOW` (private ranges by default).

| Metric | Use it for |
|--------|-----------|
| `gateway_http_requests_total{server,upstream,status}` | Traffic and error ratio per route. |
| `gateway_http_request_duration_seconds` | Latency seen by clients. |
| `gateway_upstream_response_duration_seconds{upstream}` | Backend latency (summed across retries). |
| `nginx_upstream_status_info{name,endpoint,status}` | Peer health. |
| `gateway_config_valid`, `gateway_config_fallback` | Whether `conf.d` is the config being served. |
| `gateway_connections{state}` | Client connections. |

Suggested alerts:

| Alert | Condition |
|-------|-----------|
| Config not applied | `gateway_config_fallback == 1` for more than 5 minutes |
| Upstream down | an upstream with no peer in `status="UP"` |
| Gateway 5xx ratio | above 1%: investigate. Above 5%: page. |

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `GATEWAY_WATCH_CONFIG` | `true` | Validate and publish `conf.d` on change. |
| `GATEWAY_WATCH_INTERVAL` | `5` | Seconds between config checks. |
| `GATEWAY_RESOLVER` | from `/etc/resolv.conf` | DNS server(s) for `resolve` upstreams (IPs; IPv6 in brackets). |
| `GATEWAY_RESOLVER_VALID` | `10s` | How long a DNS answer is trusted. |
| `GATEWAY_REAL_IP_FROM` | — | Trusted proxies (IPs/CIDRs). Empty means edge mode. |
| `GATEWAY_STATUS_ALLOW` | private ranges | Who can reach `:8081` (IPs/CIDRs, or `all`). |
| `GATEWAY_CLIENT_MAX_BODY_SIZE` | `10m` | Default request body limit (override per server/location). |
| `GATEWAY_WORKER_PROCESSES` | container CPU limit | Worker count; defaults to the cgroup CPU quota, or `auto` without one. |
| `GATEWAY_WORKER_SHUTDOWN_TIMEOUT` | `30s` | How long a stop or reload waits for in-flight requests and WebSockets. |
| `GATEWAY_ACCESS_LOG_STDOUT` | `false` | Also write the JSON access log to stdout (`docker logs`). |
| `LOGROTATE_FREQUENCY` | `daily` | `hourly`, `daily`, `weekly`, `monthly`, or `size` to rotate only by size. |
| `LOGROTATE_MAXSIZE` | `1G` | With a schedule: also rotate early above this size (empty disables). With `size`: the only trigger. |
| `LOGROTATE_ROTATE` | `30` | Rotated files kept per log. |
| `LOGROTATE_COMPRESS` | `true` | Gzip rotated files. |
| `LOGROTATE_DELAY_SECONDS` | `300` | How often logrotate checks whether a rotation is due. |
| `LOGROTATE_STATE_FILE` | `/var/log/nginx/.logrotate.status` | Rotation state, kept with the logs. |

Every value is validated at startup. An invalid one stops the container with a message naming the variable.

## Logs

- `access.log` holds one JSON object per request: request id, upstream address and status, timings.
- `error.log` is written to the file **and** to stderr, so `docker logs` shows gateway errors.
- Set `GATEWAY_ACCESS_LOG_STDOUT=true` to also ship access logs through the container runtime.
- Size the disk for `LOGROTATE_ROTATE × LOGROTATE_MAXSIZE` per log file. With the defaults that is up to 30 GB per log, so lower one of the two on small disks.

## Production checklist

- [ ] Every `server` in your upstreams has `resolve` and every upstream has a `zone`.
- [ ] Each health check `path` answers 200 on a healthy backend. Check `/status/upstreams` after deploying.
- [ ] `GATEWAY_REAL_IP_FROM` is set if a load balancer sits in front, so per-IP limits and logs see real clients.
- [ ] Port 8081 is not published to the internet; Prometheus scrapes it from the internal network.
- [ ] `stop_grace_period` (Compose/Swarm) or `terminationGracePeriodSeconds` (Kubernetes) is longer than `GATEWAY_WORKER_SHUTDOWN_TIMEOUT`.
- [ ] `/var/log/nginx` is a volume, with rotation sized for the disk. A host directory must be writable by uid 101 (`sudo chown 101:101 logs`).
- [ ] CPU and memory limits are set; the worker count follows the CPU limit.
- [ ] Alerts are configured for `gateway_config_fallback`, peers DOWN and the 5xx ratio.
- [ ] TLS is terminated at the gateway or at the load balancer in front (see the commented `listen 443 ssl` example in `examples/api.conf`).
- [ ] Config changes go through review. The gateway rejects broken files, but it cannot tell a wrong route from a right one.

## Extending

OpenResty runs Lua in every request phase, which is where the gateway grows. Some usual next steps, with what each one costs:

| Capability | How | Cost |
|------------|-----|------|
| JWT validation | `lua-resty-jwt` or `lua-resty-openidc` in an `access_by_lua_block` per location | Medium: key rotation, clock skew, error mapping |
| API keys from a file | a `map` from `$http_x_api_key` to a consumer name in `conf.d` | Low: no code, keys live in a mounted file |
| Response caching | `proxy_cache_path` + `proxy_cache` per location, `proxy_cache_use_stale` for degradation | Medium: invalidation, never cache authenticated responses |
| CORS | a `routes/cors.inc` include with `more_set_headers` and an `OPTIONS` short-circuit | Low |
| Circuit breaker beyond health checks | `max_fails` + `max_conns` already cover most cases; a Lua breaker is rarely worth its upkeep | High |

## Testing

`../test-apigateway/test.sh` brings the gateway up with a static pool and a DNS-discovered pool, then checks the behaviour end to end:
- routing and failover;
- scaling;
- hot reload, with invalid configs and a broken `healthchecks.json`;
- restart on a bad config;
- JSON errors, rate limiting and spoofed headers;
- metrics and graceful stop.

It exits non-zero on any failure, and CI runs it before publishing any image.

## Version coupling

The OpenResty tag is `<nginx-core>.<resty-revision>`. Brotli is compiled against the vanilla nginx source given by `ARG NGINX_CORE_VERSION`, verified with `ARG NGINX_CORE_SHA256`. Bump both together with the `FROM` tag or the build fails, or the module will not load.

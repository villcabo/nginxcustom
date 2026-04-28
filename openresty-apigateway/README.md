# OpenResty API Gateway

Drop-in API gateway image based on **OpenResty 1.29.2.3** (nginx core 1.29.2 + Lua), with the same operational ergonomics as the other images in this repo (logrotate, env-var tunables, non-root, multi-arch) plus first-class active health checking — Traefik-style.

## What's inside

- **OpenResty 1.29.2.3** on Debian Bookworm (`openresty/openresty:1.29.2.3-bookworm-fat`)
  - `lua-nginx-module`, `lua-resty-core`, `lua-resty-upstream-healthcheck`, `lua-resty-balancer`, etc. — bundled.
  - LuaRocks + OPM available for installing extra Lua libs at runtime (e.g. `lua-resty-jwt`, `lua-resty-redis`) without recompiling.
- **GeoIP2** dynamic module (`ngx_http_geoip2_module.so`) — compiled against matching nginx core.
- **Brotli** dynamic modules (`ngx_http_brotli_filter_module.so`, `ngx_http_brotli_static_module.so`).
- **logrotate** + a background loop driven by env vars (no cron daemon).
- Runs as the unprivileged `nginx` user on port `8080`. PID file in `/tmp/nginx.pid`. `STOPSIGNAL SIGQUIT` for graceful drain.

## Why this image (vs `nginx-logrotate-geoip`)

The plain nginx OSS images can only do **passive** health checks — a backend is discovered to be down when a real request fails. With OpenResty's bundled `lua-resty-upstream-healthcheck`, this image does **active** probes (HTTP GET, every N seconds) so a dead peer is marked DOWN *before* a client request arrives. Combined with `proxy_next_upstream`, failover becomes invisible to the client — same UX as Traefik.

## Build & run

```bash
./build.sh apigateway

docker run -d --name openresty-apigateway -p 8080:8080 \
  -e LOGROTATE_DELAY_SECONDS=3600 \
  -e LOGROTATE_MAXSIZE=1G \
  villcabo/openresty-apigateway:1.29.2.3-bookworm-fat-beta
```

## Environment variables

| Variable | Default | Description |
| --- | --- | --- |
| `LOGROTATE_DELAY_SECONDS` | `3600` | Seconds between logrotate runs. |
| `LOGROTATE_MAXSIZE` | `1G` | Max size per log file before intra-day rotation. Accepts `k`/`M`/`G`. |

## Active health check (the headline feature)

The shipped `apigateway-example.conf` demonstrates a Traefik-style upstream pool:

```nginx
# Inside http {}:
lua_shared_dict healthcheck 1m;

init_worker_by_lua_block {
    local hc = require "resty.upstream.healthcheck"
    hc.spawn_checker{
        shm = "healthcheck",
        upstream = "backend_api",
        type = "http",
        http_req = "GET /health HTTP/1.0\r\nHost: backend\r\n\r\n",
        interval = 2000,   -- ping every 2s
        timeout = 1000,
        fall = 2, rise = 2,
        valid_statuses = {200, 204},
    }
}

upstream backend_api {
    server backend1:8080 max_fails=1 fail_timeout=10s;
    server backend2:8080 max_fails=1 fail_timeout=10s;
    keepalive 32;
}
```

**Behavior:**
- Each worker pings every backend every 2s (configurable).
- `fall=2` consecutive failures → peer marked DOWN, removed from pool.
- `rise=2` consecutive successes → peer marked UP again.
- All workers share state via `lua_shared_dict healthcheck`.
- Combined with `proxy_next_upstream error timeout http_502 http_503` and low `proxy_connect_timeout`, the client never sees a failed upstream.

The example config also shows a `/healthcheck-status` admin endpoint and a basic `limit_req_zone` for per-IP rate limiting.

## What's NOT in this image (Phase 2)

JWT validation (`lua-resty-jwt`), OAuth flows, response transformation, advanced caching. These can be installed on top of the running container via:

```bash
opm get SkyLothar/lua-resty-jwt
# or
luarocks install lua-resty-jwt
```

…but a follow-up version of this image will bake them in as a proper "API gateway feature pack."

## Files

| File | Purpose |
| --- | --- |
| `Dockerfile` | Build definition. |
| `entrypoint.sh` | Runtime: validate config, patch logrotate from env vars, start logrotate loop, exec OpenResty. |
| `logrotate.conf` | Same rotation policy as the other images. |
| `apigateway-example.conf` | Reference upstream + health check + rate limit config. NOT loaded automatically. |

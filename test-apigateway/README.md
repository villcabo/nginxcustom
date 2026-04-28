# OpenResty API Gateway — Failover Validation Harness

End-to-end test for the active health check + transparent failover behavior of `openresty-apigateway/`. Spins up the gateway with two mock backends that simulate Spring-Boot-style cold starts (~25s before they answer `/health`), then continuously probes the gateway while you kill and resurrect backends.

## What gets tested

- **Cold-start handling.** Backends sleep 25s before serving. The gateway's healthchecker probes every 2s; peers stay marked DOWN until they actually answer `/health`. The gateway must not forward client traffic to them during this window.
- **Active failover.** Once both peers are UP, killing one (`docker compose stop backend1`) must NOT produce 502/504 to the client. The healthchecker detects DOWN within `interval * fall = 4s`; combined with `proxy_next_upstream`, retry on the live peer is invisible.
- **Recovery.** Restarting a stopped backend should put it back into the pool after `interval * rise = 4s` once it's actually answering 200 again.

## Topology

```
            +-------------------+
            |  apigw-gateway    |  :8080  (host port published)
            |  openresty-apigw  |
            |  active hc 2s     |
            +---------+---------+
                      |
              +-------+-------+
              |               |
       +------v-----+   +-----v------+
       | backend1   |   | backend2   |
       | nginx +    |   | nginx +    |
       | sleep 25s  |   | sleep 25s  |
       +------------+   +------------+
```

## Run

```bash
# Terminal 1: build images and bring everything up
docker compose up --build

# Terminal 2: continuous probe (waits for UP, then loops curl every 5s)
./test-failover.sh
```

## What you should see

**Phase 1 — boot.** The script polls `/healthcheck-status` and waits up to 90s for both peers to be UP. While the backends are still sleeping you'll see DOWN entries — that's correct. They flip to UP within ~4s of the backend actually starting to answer `/health`.

**Phase 2 — steady state.** Once UP, the loop prints lines like:

```
[14:02:15] HTTP 200 t=0.012s  "backend":"backend1"  {"backend":"backend1","host":"a1b2c3..."}
[14:02:20] HTTP 200 t=0.011s  "backend":"backend2"  {"backend":"backend2","host":"d4e5f6..."}
```

You should see backend1 / backend2 alternating (round-robin by default).

**Phase 3 — kill one.** In a third terminal:

```bash
docker compose stop backend1
```

The healthchecker marks backend1 DOWN within ~4s. The probe loop should:
- **Never produce HTTP 502/503/504** — every line stays HTTP 200.
- **Only show backend2** answering from now on.
- Optionally, the *first* request after the kill may have slightly higher `t=` (the request that raced the healthcheck retries via `proxy_next_upstream`).

**Phase 4 — recover.**

```bash
docker compose start backend1
```

Wait ~25s for the cold start. ~4s after backend1 starts answering `/health`, you should see it returning to the rotation.

## Inspect health-check state directly

```bash
curl -s http://localhost:8080/healthcheck-status
```

Sample output:

```
Worker PID: 17
Upstream backend_api
  Primary Peers
    backend1:8080 UP
    backend2:8080 DOWN
  Backup Peers
```

## Tunables

| Knob                 | Where                       | Default |
|----------------------|-----------------------------|---------|
| Probe interval       | `nginx.conf` `interval`     | 2000ms  |
| Probe timeout        | `nginx.conf` `timeout`      | 1000ms  |
| Failures → DOWN      | `nginx.conf` `fall`         | 2       |
| Successes → UP       | `nginx.conf` `rise`         | 2       |
| Cold-start delay     | compose `STARTUP_DELAY`     | 25s     |
| Probe loop interval  | env `INTERVAL` for script   | 5s      |

## Cleanup

```bash
docker compose down -v
```

## Files

| File                       | Role                                                       |
|----------------------------|------------------------------------------------------------|
| `docker-compose.yml`       | Three-service topology (gateway + 2 backends).             |
| `nginx.conf`               | Gateway config mounted over OpenResty default.             |
| `backend/Dockerfile`       | Mock backend image (alpine nginx + delay).                 |
| `backend/start.sh`         | Sleep STARTUP_DELAY, render conf from template, exec nginx.|
| `backend/default.conf.tmpl`| Template with `__BACKEND_ID__` placeholder.                |
| `test-failover.sh`         | Wait-for-up + continuous probe loop.                       |

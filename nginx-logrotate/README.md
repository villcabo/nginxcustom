# nginx-logrotate

Official Nginx 1.31 on Alpine (`FROM nginx:1.31-alpine`) plus `logrotate`, running as a non-root user. No extra Nginx modules.

- Runs as the `nginx` user, listens on `80`, pid file at `/tmp/nginx.pid`.
- Generates its logrotate configuration at startup from environment variables.
- Rotates in-process (a background loop in the entrypoint), with no cron daemon.
- `HEALTHCHECK` against `http://127.0.0.1/`.

## When to use it

Use it as a reverse proxy or to serve static files when you want rotated log files on a volume and a non-root container.

- Need GeoIP2 or Brotli? Use [`nginx-logrotate-geoip`](../nginx-logrotate-geoip/README.md).
- Need an API gateway with active upstream health checks and failover? Use [`openresty-apigateway`](../openresty-apigateway/README.md).

## Quick start

```bash
docker run -d --name nginx-logrotate -p 8080:80 villcabo/nginx-logrotate:1.31-alpine
curl -I http://localhost:8080/
```

The tag is the one after the colon in the `FROM` line (`1.31-alpine`). Images built locally with `./build.sh` get a `-beta` suffix.

### docker-compose.yml

Custom configuration in `conf.d` and logs in a host directory:

```yaml
services:
  nginx:
    image: villcabo/nginx-logrotate:1.31-alpine
    container_name: nginx
    stop_grace_period: 30s
    restart: unless-stopped
    ports:
      - "8080:80"
    volumes:
      - ./conf.d:/etc/nginx/conf.d:ro
      - ./logs:/var/log/nginx
    mem_limit: 256m
    cpus: 1.0
    environment:
      LOGROTATE_FREQUENCY: daily
      LOGROTATE_MAXSIZE: 1G
      LOGROTATE_ROTATE: 30
    healthcheck:
      test: ["CMD", "wget", "-q", "-O", "/dev/null", "http://127.0.0.1/"]
      interval: 30s
      timeout: 5s
      retries: 3
```

Validate it with `docker compose config -q` before bringing it up.

## Custom configuration

Mount your own files over `/etc/nginx/conf.d`. This replaces the default `default.conf` entirely.

```nginx
# ./conf.d/app.conf
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://backend:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Rules to keep the image working:

- **Listen on `80`** (and `443` for TLS). The container runs as the non-root `nginx` user and can still bind them, because Docker sets `net.ipv4.ip_unprivileged_port_start=0` in every container's network namespace. That does not apply with `--network host` (the bind fails with `Permission denied`) or on Kubernetes, where the pod must declare that sysctl in its `securityContext`. Choose the host side freely: `-p 80:80`, `-p 8080:80`.
- Run `nginx -t` against your files before deploying. The entrypoint also validates the configuration at startup and exits with an error if it is invalid.
- If you replace the whole `/etc/nginx/nginx.conf`, keep `pid /tmp/nginx.pid;` and do not set a `user` directive. The log rotation signals Nginx through `/tmp/nginx.pid`.
- Custom `access_log`/`error_log` paths are only rotated if they are under `/var/log/nginx` (see below).

## Environment variables

The logrotate configuration is generated at startup. Invalid values stop the container with an error message.

| Variable | Default | Description |
| --- | --- | --- |
| `LOGROTATE_FREQUENCY` | `daily` | `hourly`, `daily`, `weekly`, `monthly` to rotate on that schedule, or `size` to rotate only by size. |
| `LOGROTATE_MAXSIZE` | `1G` | With a schedule: also rotate early when a file exceeds it (set it empty to disable). With `size`: the only trigger and required. Format `<number>[k\|M\|G]`, for example `500k`, `100M`, `1G`. |
| `LOGROTATE_ROTATE` | `180` | Number of rotated files to keep per log. Integer. |
| `LOGROTATE_COMPRESS` | `true` | Gzip rotated files (the newest one stays uncompressed for one cycle). Any value other than `true` disables compression. |
| `LOGROTATE_DELAY_SECONDS` | `300` | How often the loop checks whether a rotation is due. It never forces a rotation, so keep it well below the smallest trigger. |
| `LOGROTATE_STATE_FILE` | `/var/log/nginx/.logrotate.status` | logrotate state file. It lives with the logs so schedules survive restarts when `/var/log/nginx` is a volume. |

## Logs and rotation

In the official Nginx image, `/var/log/nginx/access.log` and `error.log` are **symlinks to stdout and stderr**. To get real files to rotate, **bind-mount a host directory** on `/var/log/nginx`. The mount hides the symlinks and Nginx writes regular files there.

```yaml
volumes:
  - ./logs:/var/log/nginx
```

Do **not** use a named volume for this. Docker initialises an empty named volume by copying the image's directory into it, symlinks included, so the logs keep going to stdout and nothing is ever rotated (verified on `1.31-alpine`). The host directory must be writable by the container's `nginx` user, uid 101: `mkdir logs && sudo chown 101:101 logs`.

What gets rotated: `/var/log/nginx/*.log`, `*/*.log`, `*.json` and `*/*.json`. The generated rules also use `dateext` (rotated files look like `access.log-20261007-1791234567`), `create 0640`, `missingok` and `notifempty`. After each rotation the entrypoint signals Nginx with `USR1` so it reopens its files.

### Rotate by day

Once a day, never early:

```bash
docker run -d -p 8080:80 -v "$PWD/logs:/var/log/nginx" \
  -e LOGROTATE_FREQUENCY=daily \
  -e LOGROTATE_MAXSIZE= \
  -e LOGROTATE_ROTATE=30 \
  villcabo/nginx-logrotate:1.31-alpine
```

### Rotate by size

Only when a file exceeds 500 MB:

```bash
docker run -d -p 8080:80 -v "$PWD/logs:/var/log/nginx" \
  -e LOGROTATE_FREQUENCY=size \
  -e LOGROTATE_MAXSIZE=500M \
  villcabo/nginx-logrotate:1.31-alpine
```

### Rotate by day and by size

The default behavior: at least once a day, and earlier whenever a file exceeds the limit.

```bash
docker run -d -p 8080:80 -v "$PWD/logs:/var/log/nginx" \
  -e LOGROTATE_FREQUENCY=daily \
  -e LOGROTATE_MAXSIZE=1G \
  villcabo/nginx-logrotate:1.31-alpine
```

The startup log prints the effective values, for example `logrotate: frequency=daily maxsize=1G keep=180 compress=true check_every=300s`. Check them with `docker logs <container> | rg logrotate`.

To see what is on disk: `docker exec <container> ls -la /var/log/nginx`.

## Healthcheck

The image defines `HEALTHCHECK --interval=30s --timeout=5s` running `wget -q -O /dev/null http://127.0.0.1/`.

`wget` fails on 4xx and 5xx responses. If your `conf.d` does not answer `2xx`/`3xx` on `/` (for example, a pure API that returns `404` there), the container will be reported `unhealthy`. Override the check in compose or `docker run` (`--health-cmd`) with an endpoint you do have. If you change the listening port, change the healthcheck too.

## Production recommendations

- **Mount the logs** (`/var/log/nginx`) as a volume, otherwise nothing is rotated and logs only go to `docker logs`.
- **Set `stop_grace_period`** (for example `30s`). `docker stop` sends `SIGQUIT`, which makes Nginx finish in-flight requests before exiting. The default 10 seconds may cut long requests. The `SIGQUIT` stop signal is inherited from the official Nginx image.
- **Keep it non-root.** Do not add `user: root`. Mount configuration read-only (`:ro`).
- **Limit resources** (`mem_limit`, `cpus` in compose, or `--memory` and `--cpus`). Size them for your traffic; the values above are a starting point.
- **Pin the tag** to a version, and rebuild regularly to pick up Alpine and Nginx security fixes.
- Set `LOGROTATE_ROTATE` and `LOGROTATE_MAXSIZE` according to the disk you give the logs volume: worst case is about `LOGROTATE_ROTATE x LOGROTATE_MAXSIZE` per log.

## Build locally

```bash
./build.sh logrotate              # builds nginx-logrotate/
./build.sh logrotate --no-cache
```

The script builds a multi-arch image and names it `$DOCKER_USERNAME/nginx-logrotate:<tag>-beta`, taking the tag from the `FROM` line (`1.31-alpine`). See the root [README](../README.md) for the other images.

# nginx-logrotate-geoip

Official Nginx 1.31.6 on Debian Trixie (`FROM nginx:1.31.6-trixie`) with logrotate and three dynamic modules compiled from source against the matching Nginx tarball, running as a non-root user.

- Runs as the `nginx` user, listens on `80`, pid file at `/tmp/nginx.pid`.
- Generates its logrotate configuration at startup from environment variables and rotates in-process, with no cron daemon.
- `HEALTHCHECK` against `http://127.0.0.1/`.
- Graceful shutdown: the entrypoint traps `SIGTERM`, `SIGINT` and `SIGQUIT` and runs `nginx -s quit`, so `docker stop` drains connections instead of killing Nginx.

## When to use it

Use it as a reverse proxy or static server when you need IP geolocation (country or city) or Brotli compression, plus rotated logs on a volume.

- Do not need those modules? Use the lighter [`nginx-logrotate`](../nginx-logrotate/README.md) (Alpine).
- Need an API gateway with active upstream health checks and failover? Use [`openresty-apigateway`](../openresty-apigateway/README.md).

## Included modules

| Module file (`/etc/nginx/modules/`) | Purpose |
| --- | --- |
| `ngx_http_geoip2_module.so` | Geolocation from MaxMind GeoIP2/GeoLite2 `.mmdb` databases (country, city, ASN, etc.). |
| `ngx_http_brotli_filter_module.so` | On-the-fly Brotli compression (`brotli on`). |
| `ngx_http_brotli_static_module.so` | Serves pre-compressed `.br` files (`brotli_static on`). |

**The modules are not loaded by default.** They need an explicit `load_module` line in the main context of `nginx.conf`, and the databases are not in the image (see below).

## Quick start

```bash
docker run -d --name nginx-geoip -p 8080:80 villcabo/nginx-logrotate-geoip:1.31.6-trixie
curl -I http://localhost:8080/
```

With the default configuration the image runs like a plain Nginx; the startup log lists whether each module file is available. To use the modules, follow the next sections.

### docker-compose.yml

```yaml
services:
  nginx:
    image: villcabo/nginx-logrotate-geoip:1.31.6-trixie
    container_name: nginx-geoip
    stop_grace_period: 30s
    restart: unless-stopped
    ports:
      - "8080:80"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./conf.d:/etc/nginx/conf.d:ro
      - ./geoip:/usr/share/GeoIP:ro
      - ./logs:/var/log/nginx
    mem_limit: 512m
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

## Loading the modules

`load_module` is only valid in the main context. Placed inside `http {}` it is a fatal error. For that reason the reference file shipped in the image is **not** in `conf.d`: it is at `/etc/nginx/examples/modules.conf` and is never included automatically.

The official image's `nginx.conf` does not load anything from `/etc/nginx/modules`, so mount your own `nginx.conf` and keep `conf.d` for the rest. This one is based on the official default plus the `load_module` lines:

```nginx
# ./nginx.conf
load_module modules/ngx_http_geoip2_module.so;
load_module modules/ngx_http_brotli_filter_module.so;
load_module modules/ngx_http_brotli_static_module.so;

worker_processes auto;

error_log /var/log/nginx/error.log notice;
pid /tmp/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    keepalive_timeout 65;

    include /etc/nginx/conf.d/*.conf;
}
```

Rules when replacing `nginx.conf`:

- Keep `pid /tmp/nginx.pid;`. The log rotation signals Nginx through that file.
- Do not set a `user` directive (the container is not root).
- **Listen on `80`** (and `443` for TLS). The container runs as the non-root `nginx` user and can still bind them, because Docker sets `net.ipv4.ip_unprivileged_port_start=0` in every container's network namespace. That does not apply with `--network host` (the bind fails with `Permission denied`) or on Kubernetes, where the pod must declare that sysctl in its `securityContext`. Choose the host side freely: `-p 80:80`, `-p 8080:80`.

To copy the reference example out of the image: `docker run --rm --entrypoint cat villcabo/nginx-logrotate-geoip:1.31.6-trixie /etc/nginx/examples/modules.conf`. It contains `load_module` lines **and** an `http {}` block, so it is a reference to read, not a file to mount as is (it has no `events {}` block).

## GeoIP2

### Mounting the databases

The MaxMind `.mmdb` files are **not** in the image and require a MaxMind account and license (GeoLite2 is free but needs registration). Download them with `geoipupdate` or from your MaxMind account, extract the `.mmdb` files into a host directory and mount it:

```
geoip/
├── GeoLite2-Country.mmdb
└── GeoLite2-City.mmdb
```

```bash
-v "$PWD/geoip:/usr/share/GeoIP:ro"
```

`auto_reload 5m` in the `geoip2` block makes Nginx pick up a replaced file without a restart. Keep the databases updated, MaxMind publishes new ones regularly.

### Country and city

Put this in `conf.d/geoip.conf` (it is included inside `http {}`):

```nginx
geoip2 /usr/share/GeoIP/GeoLite2-Country.mmdb {
    auto_reload 5m;
    $geoip2_data_country_code default=XX source=$remote_addr country iso_code;
    $geoip2_data_country_name country names en;
}

geoip2 /usr/share/GeoIP/GeoLite2-City.mmdb {
    $geoip2_data_city_name default=Unknown city names en;
    $geoip2_data_postal_code postal code;
    $geoip2_data_latitude location latitude;
    $geoip2_data_longitude location longitude;
    $geoip2_data_time_zone location time_zone;
}
```

If Nginx sits behind another proxy or load balancer, `$remote_addr` is the proxy address. Use `source=$http_x_forwarded_for` only when that header comes from a proxy you trust, otherwise clients can spoof their country.

### Test endpoint

Handy while setting it up. Add it to a `server {}` block:

```nginx
location /geoip-status {
    default_type application/json;
    return 200 '{"country_code":"$geoip2_data_country_code","country_name":"$geoip2_data_country_name","city":"$geoip2_data_city_name","latitude":"$geoip2_data_latitude","longitude":"$geoip2_data_longitude"}';
}
```

```bash
curl http://localhost:8080/geoip-status
```

Remove it, or restrict it, before going to production.

### Block or allow by country

```nginx
map $geoip2_data_country_code $country_allowed {
    default 0;
    BO 1;
    AR 1;
    PE 1;
}

server {
    listen 80;

    if ($country_allowed = 0) {
        return 403;
    }

    location / {
        root /usr/share/nginx/html;
    }
}
```

To block a few countries instead, invert it: `default 1;` and list the blocked codes with `0`.

### Route or map by country

The same variable can select an upstream, a language or a header:

```nginx
map $geoip2_data_country_code $backend {
    default app_global;
    BO app_bolivia;
}

server {
    listen 80;

    location / {
        proxy_pass http://$backend;
        proxy_set_header X-Country-Code $geoip2_data_country_code;
    }
}
```

`proxy_pass` with a variable needs the names to exist as `upstream` blocks (or a `resolver` for plain hostnames).

### Country in the access log

```nginx
log_format geo '$remote_addr [$time_local] "$request" $status '
               'country=$geoip2_data_country_code city="$geoip2_data_city_name"';

access_log /var/log/nginx/access.log geo;
```

## Brotli

```nginx
brotli on;
brotli_comp_level 6;
brotli_buffers 16 8k;
brotli_min_length 20;
brotli_types
    text/plain
    text/css
    text/xml
    text/javascript
    text/json
    application/json
    application/javascript
    application/xml+rss
    application/atom+xml
    image/svg+xml;

server {
    listen 80;

    location / {
        root /usr/share/nginx/html;
        index index.html;
        brotli_static on;
    }
}
```

`text/html` is always compressed when `brotli on`. `brotli_static on` serves `file.css.br` next to `file.css` when the client sends `Accept-Encoding: br`; it needs the `.br` files to exist (create them at build time, for example with `brotli -k file.css`).

Test it:

```bash
curl -s -o /dev/null -D - -H "Accept-Encoding: br" http://localhost:8080/ | rg -i content-encoding
```

For text content, Brotli usually compresses noticeably better than gzip at similar levels, at higher CPU cost for high `brotli_comp_level` values. Level 4 to 6 is a reasonable range for dynamic content.

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

What gets rotated: `/var/log/nginx/*.log`, `*/*.log`, `*.json` and `*/*.json`. The generated rules also use `dateext` (files look like `access.log-20261007-1791234567`), `create 0640`, `missingok` and `notifempty`, and Nginx is signalled with `USR1` after each rotation.

Examples (all with `-v "$PWD/logs:/var/log/nginx"`):

```bash
# By day, never early
-e LOGROTATE_FREQUENCY=daily -e LOGROTATE_MAXSIZE= -e LOGROTATE_ROTATE=30

# By size only (500 MB)
-e LOGROTATE_FREQUENCY=size -e LOGROTATE_MAXSIZE=500M

# By day and by size (default behavior)
-e LOGROTATE_FREQUENCY=daily -e LOGROTATE_MAXSIZE=1G
```

The startup log prints the effective values: `docker logs <container> | rg logrotate`.

## Healthcheck

`HEALTHCHECK --interval=30s --timeout=5s` runs `wget -q -O /dev/null http://127.0.0.1/`. `wget` fails on 4xx and 5xx, so if your configuration does not answer `2xx`/`3xx` on `/`, the container will show as `unhealthy`: override the check with an endpoint that exists. If you change the listening port, change the healthcheck too.

## Production recommendations

- **Mount the logs** (`/var/log/nginx`) as a volume, otherwise nothing is rotated.
- **Set `stop_grace_period`** (for example `30s`). `docker stop` sends `SIGQUIT` and the entrypoint runs `nginx -s quit`, which finishes in-flight requests. The default 10 seconds can cut long ones.
- **Keep it non-root** and mount configuration and databases read-only (`:ro`).
- **Limit resources** (`mem_limit`, `cpus`, or `--memory` and `--cpus`). Each `geoip2` database is memory-mapped, and Brotli at high levels uses more CPU; size according to your traffic.
- **Pin the tag** and rebuild regularly to pick up Debian and Nginx security fixes.
- Do not commit `.mmdb` files or MaxMind license keys to git.

## Validation

`validate-image.sh` checks a built image: that it exists, that the three `.so` files are present and load with `nginx -t`, that the runtime libraries (libmaxminddb, libbrotli, libpcre) resolve, that `/etc/nginx/examples/modules.conf` is included, the `nginx -V` output, and that the container starts with the default configuration, answers on `80` and generates `/etc/logrotate.d/nginx`.

```bash
./validate-image.sh villcabo/nginx-logrotate-geoip:1.31.6-trixie-beta
```

Without an argument it uses `villcabo/nginx-logrotate-geoip:1.31.6-trixie-beta`.

## Build locally

```bash
./build.sh logrotate-geoip
./build.sh logrotate-geoip --no-cache
```

The script builds a multi-arch image named `$DOCKER_USERNAME/nginx-logrotate-geoip:<tag>-beta`, with the tag taken from the `FROM` line (`1.31.6-trixie`). The build compiles the modules, so it takes noticeably longer than the Alpine image.

### Why the tarball version must match the `FROM`

Nginx dynamic modules are only loadable by the exact Nginx version they were built against. The Dockerfile downloads `nginx-<version>.tar.gz` from nginx.org and runs `./configure --with-compat` and `make modules` on it. If that version differs from the `FROM nginx:<version>-trixie` base, Nginx refuses to start with a `module ... is not binary compatible` error.

When bumping Nginx, change **both** in the same commit: the `FROM` tag and the tarball version (the `wget .../nginx-X.Y.Z.tar.gz`, `tar`, `mv` and `rm` lines of the module build step). Then run `./validate-image.sh` on the result.

The GeoIP2 and Brotli module sources are cloned from their default branches at build time, so two builds on different days may compile different module code.

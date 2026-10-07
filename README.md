# Nginx Docker Images

This repository contains custom Docker images for Nginx with additional features:

- **Nginx + Logrotate**: Nginx with automatic log rotation using logrotate.
- **Nginx + Logrotate + GeoIP**: Nginx with log rotation, GeoIP2 and Brotli modules.
- **OpenResty API Gateway**: OpenResty (nginx + Lua) with GeoIP2, Brotli, logrotate, and active upstream health checks (Traefik-style failover).

## Features

- Automated log rotation for Nginx logs using logrotate and cron.
- Easy to extend and customize.
- Optional GeoIP support for IP-based geolocation.

## Usage

### 1. Nginx + Logrotate

This image runs Nginx and rotates logs based on a configurable interval and size threshold.

**Build the image:**

```bash
docker build -t nginx-logrotate ./nginx-logrotate
```

**Run the container:**

```bash
docker run -d --name nginx-logrotate -p 8080:8080 \
  -e LOGROTATE_FREQUENCY=daily \
  -e LOGROTATE_MAXSIZE=1G \
  nginx-logrotate
```

### 2. Nginx + Logrotate + GeoIP

This image includes GeoIP support in addition to log rotation.

**Build the image:**

```bash
docker build -t nginx-logrotate-geoip ./nginx-logrotate-geoip
```

**Run the container:**

```bash
docker run -d --name nginx-logrotate-geoip -p 8080:8080 \
  -e LOGROTATE_FREQUENCY=daily \
  -e LOGROTATE_MAXSIZE=1G \
  nginx-logrotate-geoip
```

### 3. OpenResty API Gateway

A file-driven API gateway on OpenResty (nginx + LuaJIT): routes and upstreams in plain files under `/etc/nginx/conf.d`, hot reload on change, DNS-based backend discovery (scale a service and the gateway follows), active health checks declared in JSON, JSON logs and errors, request ids and Prometheus metrics on an internal port. No GeoIP.

**Build the image:**

```bash
docker build -t openresty-apigateway ./openresty-apigateway
# or
./build.sh apigateway
```

**Run the container:**

```bash
docker run -d --name openresty-apigateway -p 8080:8080 \
  -v "$PWD/conf.d:/etc/nginx/conf.d:ro" \
  -e LOGROTATE_FREQUENCY=daily \
  -e LOGROTATE_MAXSIZE=1G \
  openresty-apigateway
```

It has its own environment variables (log rotation by schedule or by size, config watching, resolver, trusted proxies). See `openresty-apigateway/README.md` and `openresty-apigateway/examples/`.

## Environment Variables

`nginx-logrotate` and `nginx-logrotate-geoip` accept the following variables at runtime (the API gateway has its own set, see its README):

| Variable | Default | Description |
| --- | --- | --- |
| `LOGROTATE_FREQUENCY` | `daily` | `hourly`, `daily`, `weekly`, `monthly` — rotate on that schedule — or `size` to rotate only by size. |
| `LOGROTATE_MAXSIZE` | `1G` | With a schedule: also rotate early when a file exceeds it (set it empty to disable). With `size`: the only trigger. Accepts `k`/`M`/`G` (e.g. `500M`, `2G`). |
| `LOGROTATE_ROTATE` | `180` | Rotated files to keep per log. |
| `LOGROTATE_COMPRESS` | `true` | Gzip rotated files (the newest one stays uncompressed one cycle). |
| `LOGROTATE_DELAY_SECONDS` | `300` | How often logrotate checks whether a rotation is due. It never forces one, so keep it well below the smallest trigger. |
| `LOGROTATE_STATE_FILE` | `/var/log/nginx/.logrotate.status` | Rotation state; lives with the logs so schedules survive restarts. |

The config is generated at startup; invalid values stop the container with a clear error. In the official nginx base images `/var/log/nginx/*.log` are symlinks to stdout/stderr, so there is only something to rotate when `/var/log/nginx` is a mounted volume.

## Customization

- You can modify the Nginx configuration or logrotate rules by editing the files in the respective directories.
- To add more modules or change the log rotation schedule, update the Dockerfile or entrypoint scripts as needed.

## Directory Structure

```
nginxcustom/
├── nginx-logrotate/
│   ├── Dockerfile
│   ├── entrypoint.sh
│   └── ...
├── nginx-logrotate-geoip/
│   ├── Dockerfile
│   └── ...
├── openresty-apigateway/
│   ├── Dockerfile
│   ├── nginx.conf
│   ├── conf.d/
│   ├── examples/
│   ├── lualib/gateway/
│   ├── snippets/
│   └── ...
├── test-apigateway/
└── README.md
```

## License

MIT License.

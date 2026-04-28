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
  -e LOGROTATE_DELAY_SECONDS=3600 \
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
  -e LOGROTATE_DELAY_SECONDS=3600 \
  -e LOGROTATE_MAXSIZE=1G \
  nginx-logrotate-geoip
```

### 3. OpenResty API Gateway

OpenResty (nginx + LuaJIT) with GeoIP2, Brotli, logrotate, and **active upstream health checks** via the bundled `lua-resty-upstream-healthcheck` library. Use this image when you need Traefik-style transparent failover between backends — peers are probed every 2s and removed from the pool *before* a client request hits a dead one.

**Build the image:**

```bash
docker build -t openresty-apigateway ./openresty-apigateway
# or
./build.sh apigateway
```

**Run the container:**

```bash
docker run -d --name openresty-apigateway -p 8080:8080 \
  -e LOGROTATE_DELAY_SECONDS=3600 \
  -e LOGROTATE_MAXSIZE=1G \
  openresty-apigateway
```

See `openresty-apigateway/README.md` and `openresty-apigateway/apigateway-example.conf` for upstream + health check + rate limiting configuration examples.

## Environment Variables

All three images accept the following variables at runtime:

| Variable | Default | Description |
| --- | --- | --- |
| `LOGROTATE_DELAY_SECONDS` | `3600` | Interval (in seconds) at which logrotate runs in the background. Lower values give finer-grained intra-day rotation. |
| `LOGROTATE_MAXSIZE` | `1G` | Maximum size a log file can reach before being rotated within the same day. Accepts logrotate suffixes: `k`, `M`, `G` (e.g. `500M`, `2G`). Combined with `daily`, this means logs always rotate at least once per day, and additionally whenever a file exceeds this size. |

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
│   ├── apigateway-example.conf
│   └── ...
└── README.md
```

## License

MIT License.

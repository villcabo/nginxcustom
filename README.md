# Nginx Docker Images

Three hardened images built on official nginx and OpenResty. All of them:
- run as the non-root `nginx` user (uid 101) and still listen on the standard `80` (and `443` where TLS applies). Docker allows it through `net.ipv4.ip_unprivileged_port_start=0`; see each guide for `--network host` and Kubernetes;
- rotate their logs in-process with logrotate, configured from environment variables (no cron);
- ship with a Docker `HEALTHCHECK` and stop gracefully.

| Image | Base | Use it for | Guide |
|-------|------|------------|-------|
| `villcabo/nginx-logrotate` | `nginx:1.31-alpine` | Static sites and plain reverse proxying. Lean, no extra modules. | [nginx-logrotate/README.md](nginx-logrotate/README.md) |
| `villcabo/nginx-logrotate-geoip` | `nginx:1.31.6-trixie` | The same, plus GeoIP2 (country/city lookups) and Brotli as dynamic modules. | [nginx-logrotate-geoip/README.md](nginx-logrotate-geoip/README.md) |
| `villcabo/openresty-apigateway` | `openresty/openresty:1.31.1.1-bookworm-fat` | **API gateway** in front of microservices: file-driven config with validation and hot reload, last-known-good fallback, DNS discovery, active health checks, rate limiting, JSON errors, request ids, Prometheus metrics. | [openresty-apigateway/README.md](openresty-apigateway/README.md) |

## Which one?

- **Serving files or proxying to a fixed backend**: `nginx-logrotate`.
- **You need the client's country or city**: `nginx-logrotate-geoip`, with your own MaxMind databases mounted.
- **Several services behind one entry point**: `openresty-apigateway`. Open-source nginx has no active health checks, which are an NGINX Plus feature, so it only learns that a backend is dead when a client request fails on it. The gateway adds them with Lua, along with the rest of the gateway behavior.

## Logs and rotation (all images)

| Variable | Default | Description |
| --- | --- | --- |
| `LOGROTATE_FREQUENCY` | `daily` | `hourly`, `daily`, `weekly`, `monthly` — rotate on that schedule — or `size` to rotate only by size. |
| `LOGROTATE_MAXSIZE` | `1G` | With a schedule: also rotate early when a file exceeds it (set it empty to disable). With `size`: the only trigger. Accepts `k`/`M`/`G`. |
| `LOGROTATE_ROTATE` | `180` (`30` on the gateway) | Rotated files to keep per log. |
| `LOGROTATE_COMPRESS` | `true` | Gzip rotated files (the newest one stays uncompressed one cycle). |
| `LOGROTATE_DELAY_SECONDS` | `300` | How often logrotate checks whether a rotation is due. It never forces one. |
| `LOGROTATE_STATE_FILE` | `/var/log/nginx/.logrotate.status` | Rotation state; lives with the logs so schedules survive restarts. |

In the two nginx images, `/var/log/nginx/*.log` are symlinks to stdout/stderr, inherited from the official base. Bind-mount a host directory on `/var/log/nginx` to get files to rotate. A named volume copies the symlinks and rotates nothing. The gateway always writes files and also sends its error log to stderr.

## Building

```bash
./build.sh logrotate               # → nginx-logrotate/
./build.sh logrotate-geoip         # → nginx-logrotate-geoip/
./build.sh apigateway --no-cache   # → openresty-apigateway/
```

The image tag comes from the `FROM` line of each Dockerfile. Local builds and pull-request builds get a `-beta` suffix.

## Testing

```bash
./validate-image.sh villcabo/nginx-logrotate-geoip:1.31.6-trixie-beta   # modules load, container boots
./test-apigateway/test.sh                                              # gateway acceptance suite
```

CI (`.github/workflows/docker-publish.yml`) runs the gateway suite first and publishes images only if it passes: `<version>-beta` on pull requests, `<version>` on `main`.

## Repository layout

```
nginxcustom/
├── nginx-logrotate/          Dockerfile, entrypoint.sh
├── nginx-logrotate-geoip/    Dockerfile, entrypoint.sh, nginx-modules.conf
├── openresty-apigateway/     Dockerfile, entrypoint.sh, nginx.conf, lualib/gateway/, snippets/, examples/, conf.d/
├── test-apigateway/          docker compose harness + test.sh
├── build.sh                  local multi-arch build helper
└── validate-image.sh         geoip image validation
```

## License

MIT License.

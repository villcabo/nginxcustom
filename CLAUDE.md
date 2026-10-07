# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository purpose

Three custom Docker images:

- `nginx-logrotate/` — Nginx + logrotate on Alpine. Lean, no extra modules.
- `nginx-logrotate-geoip/` — Nginx + logrotate + dynamic modules (GeoIP2, Brotli filter, Brotli static) on Debian Trixie (nginx no longer publishes bookworm tags). Modules are compiled from source against the matching nginx source tarball.
- `openresty-apigateway/` — File-driven API gateway on OpenResty (nginx + LuaJIT), Debian Bookworm. No GeoIP (dropped on purpose), Brotli only. The image owns `nginx.conf`; users mount `/etc/nginx/conf.d` (routes, upstreams, `healthchecks.json`), which is hot-reloaded. DNS-based discovery via `server ... resolve`, active health checks, JSON logs/errors, Prometheus on `:8081`.

All three images run as the non-root `nginx` user, listen on `8080`, and generate their logrotate config from the same `LOGROTATE_*` env vars (the gateway keeps 30 files by default, the nginx images 180).

## Common commands

Build a module locally with the helper script (multi-arch buildx, interactive prompt, derives the tag from `FROM nginx:<v>` OR `FROM openresty/openresty:<v>`, image name = `$DOCKER_USERNAME/<dir>:<version>-beta`):

```bash
./build.sh logrotate              # → nginx-logrotate/
./build.sh logrotate-geoip        # → nginx-logrotate-geoip/
./build.sh apigateway --no-cache  # → openresty-apigateway/
```

`validate_module` tries `openresty-<name>` then `nginx-<name>`, so the bare module name maps to whichever directory exists.

Validate a built geoip image (checks module files load, runtime libs present, configs included, and that the container actually boots):

```bash
./validate-image.sh villcabo/nginx-logrotate-geoip:1.31.6-trixie-beta
```

Run a built image:

```bash
docker run -d -p 8080:8080 -e LOGROTATE_FREQUENCY=daily -e LOGROTATE_MAXSIZE=1G <image>
```

## Architecture notes

**Version coupling (geoip image).** `nginx-logrotate-geoip/Dockerfile` hardcodes the nginx source tarball version (`nginx-1.31.6.tar.gz`) and it MUST match the `FROM nginx:<version>-trixie` base. Dynamic modules compiled against a different source version will fail to load. When bumping nginx, update both the `FROM` and the `wget .../nginx-X.Y.Z.tar.gz` + extracted directory name in the same commit.

**Version coupling (apigateway image).** Same constraint, different mapping: OpenResty's version scheme is `<nginx-core>.<resty-revision>` (e.g. `1.31.1.1` → nginx core `1.31.1`). The `Dockerfile` exposes this via `ARG NGINX_CORE_VERSION=1.31.1`. When bumping the OpenResty `FROM` tag, update `NGINX_CORE_VERSION` to the matching nginx core in the same commit. Modules are compiled with `--with-compat` against vanilla nginx source so they load into the patched OpenResty nginx — works in practice because OpenResty's patches preserve module ABI, but if a future OpenResty release breaks this, fall back to compiling against the OpenResty bundle source instead of vanilla.

**Tag derivation.** Both `build.sh` and `.github/workflows/docker-publish.yml` parse the tag from the `FROM` line — first trying `nginx:<tag>`, falling back to `openresty/openresty:<tag>`. Whatever follows the colon becomes the image tag (e.g. `1.31-alpine`, `1.31.6-trixie`, `1.31.1.1-bookworm-fat`). CI appends `-beta` only on pull requests; local builds always append `-beta`.

**Non-root hardening (nginx images).** Default listen port is rewritten `80 → 8080`, the `user nginx;` directive is stripped from `nginx.conf`, the pid line is rewritten to `/tmp/nginx.pid` with a regex (`s|^pid .*|...|`) because the upstream path changes between releases (1.31 uses `/run/nginx.pid`; a literal-path sed silently no-ops and nginx then cannot start as non-root), and ownership of cache/log/conf/logrotate dirs is handed to `nginx`. The healthcheck hits `http://127.0.0.1:8080/` — NOT `localhost`, which resolves to `::1` only inside these containers while nginx listens on IPv4. The healthcheck needs `wget` at runtime: never purge it with the build deps. Logrotate `postrotate` must signal `/tmp/nginx.pid`. The geoip entrypoint (bash as PID 1) must trap `SIGQUIT`, the image `STOPSIGNAL`: without it `docker stop` waits the full grace period and SIGKILLs nginx (measured: 10.3s, exit 137).

**Logrotate runs in-process, not via cron.** Each `entrypoint.sh` renders `/etc/logrotate.d/nginx` at startup from `LOGROTATE_FREQUENCY` (`hourly|daily|weekly|monthly|size`), `LOGROTATE_MAXSIZE`, `LOGROTATE_ROTATE` and `LOGROTATE_COMPRESS`, then backgrounds a loop that runs `logrotate -s $LOGROTATE_STATE_FILE` every `LOGROTATE_DELAY_SECONDS`. Never pass `-f`: it forces a rotation on every loop and silently ignores the schedule and size (that was the behavior up to 1.29). The state file lives in `/var/log/nginx` so schedules survive restarts. `${LOGROTATE_MAXSIZE-1G}` deliberately has no colon: an empty value disables early rotation. The alpine entrypoint is busybox `sh`, so the rendering code is POSIX and kept identical in both nginx images; `/etc/logrotate.d` is chowned to `nginx` so the non-root user can write it. If you add a tunable, add it to all three entrypoints and to the READMEs.

**GeoIP2 + Brotli are dynamic modules, not loaded by default (geoip image).** They are compiled into `/etc/nginx/modules/` and require explicit `load_module` directives. The reference config is shipped at `/etc/nginx/examples/modules.conf` — never under `conf.d/`, which the stock `nginx.conf` includes inside `http {}`, where `load_module` is a fatal error. The gateway loads Brotli itself in its own `nginx.conf`.

**API gateway layout.** The image owns `/usr/local/openresty/nginx/conf/nginx.conf` (defaults, Lua phases, status server on `:8081`); users own `/etc/nginx/conf.d/*.conf` plus `conf.d/healthchecks.json`. `entrypoint.sh` renders `conf/gateway/runtime.conf` (resolver from `/etc/resolv.conf` or `GATEWAY_RESOLVER`, real_ip, body size) and the logrotate config at startup, then polls a checksum of `conf.d` and runs `openresty -t` before every reload. Lua lives in `lualib/gateway/` (`healthchecks.lua` spawns `lua-resty-upstream-healthcheck` checkers from the JSON; `metrics.lua` uses `knyar/nginx-lua-prometheus` installed via `opm` at a pinned version; `errors.lua` renders JSON error bodies). The gateway owns `init_worker_by_lua*` and `log_by_lua*` at `http` level.

**Health checks on DNS-resolved upstreams work.** `lua-resty-upstream-healthcheck` 0.08 tracks peer-list changes, so `server name resolve` pools (nginx core >= 1.27.3) get probed as replicas appear and disappear. Verified with `test-apigateway` scaling 2 → 4 → 1 with no reload and no failed requests.

**Do not set `access_log off` in the `error_page` target location.** The final location's log config applies to the whole request, so every 404/413/429/502 generated by the gateway would vanish from the access log.

**OpenResty paths to remember.** Nginx prefix is `/usr/local/openresty/nginx/`, modules in `/usr/local/openresty/nginx/modules/`, Lua in `/usr/local/openresty/site/lualib/`, binary on `$PATH` as `openresty`. pid at `/tmp/nginx.pid`. In the base image `logs/access.log` and `logs/error.log` are symlinks to stdout/stderr; the gateway writes real files under `/var/log/nginx/` instead. The official nginx images do the same symlinking for `/var/log/nginx/*.log`, so logrotate there only has real files to rotate when `/var/log/nginx` is a mounted volume.

**CI publishing.** `.github/workflows/docker-publish.yml` matrix-builds both modules. On `push` to `main` it builds both unconditionally and pushes the bare version tag. On `pull_request` it only builds modules whose directory changed and pushes `<version>-beta`. Pushes go to `${{ secrets.DOCKER_USERNAME }}/<module>`.

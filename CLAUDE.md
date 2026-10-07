# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository purpose

Three custom Docker images:

- `nginx-logrotate/` — Nginx + logrotate on Alpine. Lean, no extra modules.
- `nginx-logrotate-geoip/` — Nginx + logrotate + dynamic modules (GeoIP2, Brotli filter, Brotli static) on Debian Trixie (nginx no longer publishes bookworm tags). Modules are compiled from source against the matching nginx source tarball.
- `openresty-apigateway/` — File-driven API gateway on OpenResty (nginx + LuaJIT), Debian Bookworm. No GeoIP (dropped on purpose), Brotli only. The image owns `nginx.conf`; users mount `/etc/nginx/conf.d` (routes, upstreams, `healthchecks.json`), which is hot-reloaded. DNS-based discovery via `server ... resolve`, active health checks, JSON logs/errors, Prometheus on `:8081`.

All three images run as the non-root `nginx` user and generate their logrotate config from the same `LOGROTATE_*` env vars (the gateway keeps 30 files by default, the nginx images 180).

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

Run the gateway acceptance suite (docker compose; ~2 min, exits non-zero on failure). Any change to `openresty-apigateway/` must keep it green:

```bash
./test-apigateway/test.sh
```

Run a built image:

```bash
docker run -d -p 8080:80 -e LOGROTATE_FREQUENCY=daily -e LOGROTATE_MAXSIZE=1G <image>
```

## Architecture notes

**Version coupling (geoip image).** `nginx-logrotate-geoip/Dockerfile` hardcodes the nginx source tarball version (`nginx-1.31.6.tar.gz`) and it MUST match the `FROM nginx:<version>-trixie` base. Dynamic modules compiled against a different source version will fail to load. When bumping nginx, update both the `FROM` and the `wget .../nginx-X.Y.Z.tar.gz` + extracted directory name in the same commit.

**Version coupling (apigateway image).** Same constraint, different mapping: OpenResty's version scheme is `<nginx-core>.<resty-revision>` (e.g. `1.31.1.1` → nginx core `1.31.1`). The `Dockerfile` exposes this via `ARG NGINX_CORE_VERSION=1.31.1` plus `ARG NGINX_CORE_SHA256` (the tarball is checksum-verified) and `ARG NGX_BROTLI_COMMIT` (pinned, google/ngx_brotli has no releases). When bumping the OpenResty `FROM` tag, update `NGINX_CORE_VERSION` and its sha256 in the same commit. Modules are compiled with `--with-compat` against vanilla nginx source so they load into the patched OpenResty nginx — works in practice because OpenResty's patches preserve module ABI, but if a future OpenResty release breaks this, fall back to compiling against the OpenResty bundle source instead of vanilla.

**Tag derivation.** Both `build.sh` and `.github/workflows/docker-publish.yml` parse the tag from the `FROM` line — first trying `nginx:<tag>`, falling back to `openresty/openresty:<tag>`. Whatever follows the colon becomes the image tag (e.g. `1.31-alpine`, `1.31.6-trixie`, `1.31.1.1-bookworm-fat`). CI appends `-beta` only on pull requests; local builds always append `-beta`.

**Ports.** All images listen on the standard `80` (the gateway also `443`, status `8081`); they were on `8080` up to 1.29 and moved with the 1.31 bump. A non-root process can bind them because Docker sets `net.ipv4.ip_unprivileged_port_start=0` per container. Verified, including with `--cap-drop ALL` and `no-new-privileges`. That does not apply with `--network host` (bind fails, verified) or on Kubernetes without that sysctl in the pod `securityContext`.

**Non-root hardening (nginx images).** The stock `listen 80` is kept (see Ports), the `user nginx;` directive is stripped from `nginx.conf`, the pid line is rewritten to `/tmp/nginx.pid` with a regex (`s|^pid .*|...|`) because the upstream path changes between releases (1.31 uses `/run/nginx.pid`; a literal-path sed silently no-ops and nginx then cannot start as non-root), and ownership of cache/log/conf/logrotate dirs is handed to `nginx`. The healthcheck hits `http://127.0.0.1/` — NOT `localhost`, which resolves to `::1` only inside these containers while nginx listens on IPv4. The healthcheck needs `wget` at runtime: never purge it with the build deps. Logrotate `postrotate` must signal `/tmp/nginx.pid`. The geoip entrypoint (bash as PID 1) must trap `SIGQUIT`, the image `STOPSIGNAL`: without it `docker stop` waits the full grace period and SIGKILLs nginx (measured: 10.3s, exit 137).

**Logrotate runs in-process, not via cron.** Each `entrypoint.sh` renders `/etc/logrotate.d/nginx` at startup from `LOGROTATE_FREQUENCY` (`hourly|daily|weekly|monthly|size`), `LOGROTATE_MAXSIZE`, `LOGROTATE_ROTATE` and `LOGROTATE_COMPRESS`, then backgrounds a loop that runs `logrotate -s $LOGROTATE_STATE_FILE` every `LOGROTATE_DELAY_SECONDS`. Never pass `-f`: it forces a rotation on every loop and silently ignores the schedule and size (that was the behavior up to 1.29). The state file lives in `/var/log/nginx` so schedules survive restarts. `${LOGROTATE_MAXSIZE-1G}` deliberately has no colon: an empty value disables early rotation. The alpine entrypoint is busybox `sh`, so the rendering code is POSIX and kept identical in both nginx images; `/etc/logrotate.d` is chowned to `nginx` so the non-root user can write it. If you add a tunable, add it to all three entrypoints and to the READMEs.

**GeoIP2 + Brotli are dynamic modules, not loaded by default (geoip image).** They are compiled into `/etc/nginx/modules/` and require explicit `load_module` directives. The reference config is shipped at `/etc/nginx/examples/modules.conf` — never under `conf.d/`, which the stock `nginx.conf` includes inside `http {}`, where `load_module` is a fatal error. The gateway loads Brotli itself in its own `nginx.conf`.

**API gateway layout.** The image owns `conf/nginx.conf` (defaults, Lua phases, status server on `:8081`), which is root-owned like the rest of the prefix, modules and `site/lualib`. The runtime user writes only `/var/log/nginx`, `/var/cache/nginx` (all `*_temp_path` point there), `/etc/logrotate.d` and `conf/gateway/`. `entrypoint.sh` validates every env var, then renders three files into `conf/gateway/`: `main.conf` (worker_processes from the cgroup `cpu.max`, worker_shutdown_timeout), `runtime.conf` (resolver, body size, real_ip, the `$gateway_forwarded_*` and `$gateway_log_stdout` maps) and `status-allow.conf`. Lua lives in `lualib/gateway/`: `healthchecks.lua` validates and spawns checkers, `metrics.lua`, `errors.lua` emits JSON with a fixed key order, and `status.lua` reads `conf/gateway/status.json`.

**Config publishing (last known-good).** Users never get loaded directly. `conf/routes` is a root-owned symlink to `gateway/current`, which points to `gateway/snapshots/<id>`. On startup and on every checksum change of `/etc/nginx/conf.d`, the entrypoint does this:
1. `cp -RL` to `gateway/candidate`.
2. Runs `openresty -t -p /tmp/gateway-validate/` on a **shadow prefix**: symlinks to the real conf, with `routes` pointing at the candidate.
3. Runs `resty -e` on `gateway.validate.run`. It rejects any upstream `server <hostname>` without `resolve`; IPs, `localhost` and `unix:` are exempt. It also checks `healthchecks.json`: JSON, known options, types, and that the named upstreams exist. The JSON check is needed because `openresty -t` never runs `init_worker`.
4. Publishes with an atomic `mv -T` of the `current` symlink, then reloads.

On failure it keeps `current` and writes `state: fallback` (exposed at `/status/config` and as `gateway_config_fallback`). It survives `docker restart`, while a new container with an invalid conf.d and no snapshot exits 1. The watcher runs with `set +e +o pipefail`, because under errexit a transient `find`/`md5sum` failure used to kill it silently. Users include their own extra files as `routes/<file>`, never `/etc/nginx/conf.d/<file>`.

**Always `resolve` in gateway upstreams (enforced by `gateway.validate`).** A static `server host:port` is resolved at config load: one missing backend made the gateway refuse to start (reproduced), and a recreated backend keeps its stale IP until a reload. With `resolve` + `zone` the gateway starts with backends absent and logs `could not be resolved`.

**Edge mode vs trusted proxies.** With `GATEWAY_REAL_IP_FROM` empty, `X-Forwarded-For`/`-Proto` are overwritten with `$remote_addr`/`$scheme` (anti-spoofing). With it set, real_ip runs and the chain is appended. `X-Request-ID` is accepted only if it matches `^[A-Za-z0-9._:-]{1,128}$`.

**Health checks on DNS-resolved upstreams work.** `lua-resty-upstream-healthcheck` 0.08 tracks peer-list changes, so `server name resolve` pools (nginx core >= 1.27.3) get probed as replicas appear and disappear. Verified with `test-apigateway` scaling 2 → 4 → 1 with no reload and no failed requests.

**Do not set `access_log off` in the `error_page` target location.** The final location's log config applies to the whole request, so every 404/413/429/502 generated by the gateway would vanish from the access log.

**OpenResty paths to remember.** Nginx prefix is `/usr/local/openresty/nginx/`, modules in `/usr/local/openresty/nginx/modules/`, Lua in `/usr/local/openresty/site/lualib/`, binary on `$PATH` as `openresty`. pid at `/tmp/nginx.pid`. In the base image `logs/access.log` and `logs/error.log` are symlinks to stdout/stderr; the gateway writes real files under `/var/log/nginx/` instead. The official nginx images do the same symlinking for `/var/log/nginx/*.log`, so logrotate there only has real files to rotate when `/var/log/nginx` is a **bind mount**. A named volume does not work: Docker seeds it by copying the image directory, symlinks included (verified).

**CI publishing.** `.github/workflows/docker-publish.yml` first runs `test-apigateway/test.sh` (job `test-apigateway`; `build-and-push` needs it), then matrix-builds the three modules. On `push` to `main` it builds all of them and pushes the bare version tag. On `pull_request` it only builds modules whose directory changed and pushes `<version>-beta`. Pushes go to `${{ secrets.DOCKER_USERNAME }}/<module>`.

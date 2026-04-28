# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository purpose

Three custom Docker images:

- `nginx-logrotate/` — Nginx + logrotate on Alpine. Lean, no extra modules.
- `nginx-logrotate-geoip/` — Nginx + logrotate + dynamic modules (GeoIP2, Brotli filter, Brotli static) on Debian Bookworm. Modules are compiled from source against the matching nginx source tarball.
- `openresty-apigateway/` — OpenResty (nginx + LuaJIT) on Debian Bookworm, with the same GeoIP2/Brotli stack PLUS active upstream health checks via the bundled `lua-resty-upstream-healthcheck`. Intended for API gateway use cases where Traefik-style transparent failover is required.

All three images run as the non-root `nginx` user, listen on `8080`, and ship with the same logrotate setup and env-var tunables.

## Common commands

Build a module locally with the helper script (multi-arch buildx, interactive prompt, derives the tag from `FROM nginx:<v>` OR `FROM openresty/openresty:<v>`, image name = `$DOCKER_USERNAME/<dir>:<version>-beta`):

```bash
./build.sh logrotate              # → nginx-logrotate/
./build.sh logrotate-geoip        # → nginx-logrotate-geoip/
./build.sh apigateway --no-cache  # → openresty-apigateway/
```

`validate_module` tries `openresty-<name>` then `nginx-<name>`, so the bare module name maps to whichever directory exists.

Validate a built geoip image (checks module files load, runtime libs present, configs included):

```bash
./validate-image.sh villcabo/nginx-logrotate-geoip:1.29.0-bookworm-beta
```

Run a built image:

```bash
docker run -d -p 8080:8080 -e LOGROTATE_DELAY_SECONDS=3600 <image>
```

## Architecture notes

**Version coupling (geoip image).** `nginx-logrotate-geoip/Dockerfile` hardcodes the nginx source tarball version (`nginx-1.29.0.tar.gz`) and it MUST match the `FROM nginx:<version>-bookworm` base. Dynamic modules compiled against a different source version will fail to load. When bumping nginx, update both the `FROM` and the `wget .../nginx-X.Y.Z.tar.gz` + extracted directory name in the same commit.

**Version coupling (apigateway image).** Same constraint, different mapping: OpenResty's version scheme is `<nginx-core>.<resty-revision>` (e.g. `1.29.2.3` → nginx core `1.29.2`). The `Dockerfile` exposes this via `ARG NGINX_CORE_VERSION=1.29.2`. When bumping the OpenResty `FROM` tag, update `NGINX_CORE_VERSION` to the matching nginx core in the same commit. Modules are compiled with `--with-compat` against vanilla nginx source so they load into the patched OpenResty nginx — works in practice because OpenResty's patches preserve module ABI, but if a future OpenResty release breaks this, fall back to compiling against the OpenResty bundle source instead of vanilla.

**Tag derivation.** Both `build.sh` and `.github/workflows/docker-publish.yml` parse the tag from the `FROM` line — first trying `nginx:<tag>`, falling back to `openresty/openresty:<tag>`. Whatever follows the colon becomes the image tag (e.g. `1.29-alpine`, `1.29.0-bookworm`, `1.29.2.3-bookworm-fat`). CI appends `-beta` only on pull requests; local builds always append `-beta`.

**Non-root hardening (applied identically in both Dockerfiles).** Default listen port is rewritten `80 → 8080`, the `user nginx;` directive is stripped from `nginx.conf`, the pid file is moved to `/tmp/nginx.pid`, and ownership of cache/log/conf/logrotate dirs is handed to `nginx`. The healthcheck hits `http://localhost:8080/`. If you change the port, update the healthcheck too.

**Logrotate runs in-process, not via cron.** `entrypoint.sh` backgrounds a `while true; do sleep $LOGROTATE_DELAY_SECONDS; logrotate -vf ...; done` loop and execs nginx in the foreground. There is no cron daemon. The geoip entrypoint additionally traps SIGTERM/SIGINT for graceful `nginx -s quit`; the alpine entrypoint does not.

**Runtime-tunable logrotate via env vars.** Both entrypoints `sed`-patch `/etc/logrotate.d/nginx` on startup using:
- `LOGROTATE_DELAY_SECONDS` (default `3600`) — sleep between rotation runs.
- `LOGROTATE_MAXSIZE` (default `1G`) — replaces the `maxsize` line in the config. Combined with `daily`, this gives "rotate at least once a day, and again whenever the file exceeds this size."

The `sed` works from the non-root `nginx` user because `/etc/logrotate.d` is chowneed to `nginx` in the Dockerfile. If you add more tunables, follow the same pattern (env var → `sed` line replace) and document defaults in both `README.md` and `nginx-logrotate-geoip/README.md`.

**GeoIP2 + Brotli are dynamic modules, not loaded by default.** They are compiled into `/etc/nginx/modules/` (or `/usr/local/openresty/nginx/modules/` for the apigateway image) but require explicit `load_module` directives. The example configs (`nginx-logrotate-geoip/nginx-modules.conf`, `openresty-apigateway/apigateway-example.conf`) are shipped inside the image as references — they are NOT active unless explicitly included.

**Active health checks (apigateway only).** The OpenResty image uses the bundled `lua-resty-upstream-healthcheck` library — no extra install needed. The pattern requires three pieces in the user's nginx.conf: a `lua_shared_dict healthcheck`, an `init_worker_by_lua_block { hc.spawn_checker{...} }`, and an `upstream` block to probe. State is shared across workers via the shared dict. See `openresty-apigateway/apigateway-example.conf` for the reference setup. The lua-resty libraries live in `/usr/local/openresty/lualib/` — pre-bundled by the OpenResty package, no `opm`/`luarocks` install needed for healthcheck.

**OpenResty paths to remember.** The apigateway image deviates from the other two: nginx prefix is `/usr/local/openresty/nginx/`, modules in `/usr/local/openresty/nginx/modules/`, conf in `/usr/local/openresty/nginx/conf/`, binary on `$PATH` as `openresty`. The pid file was moved to `/tmp/nginx.pid` so logrotate's `postrotate` block must reference that path (it differs from the other two images, which still use `/var/run/nginx.pid` historically — verify before reusing the same logrotate.conf verbatim).

**CI publishing.** `.github/workflows/docker-publish.yml` matrix-builds both modules. On `push` to `main` it builds both unconditionally and pushes the bare version tag. On `pull_request` it only builds modules whose directory changed and pushes `<version>-beta`. Pushes go to `${{ secrets.DOCKER_USERNAME }}/<module>`.

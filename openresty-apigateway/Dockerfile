FROM openresty/openresty:1.31.1.1-bookworm-fat

LABEL maintainer="Bismarck Villca Soliz <bismarck.villca@gmail.com>"

# Must match the nginx core bundled by the OpenResty tag above (<core>.<resty-rev>).
# Bump NGINX_CORE_SHA256 together with it: sha256sum nginx-<version>.tar.gz
ARG NGINX_CORE_VERSION=1.31.1
ARG NGINX_CORE_SHA256=9fcaaeb8f22544b09a19a761f3412c4112215422401634bebdd1296a403cc4bc
# google/ngx_brotli has no releases; pin a reviewed commit (submodules follow it).
ARG NGX_BROTLI_COMMIT=a71f9312c2deb28875acc7bacfdd5695a111aa53
ARG PROMETHEUS_LUA_VERSION=0.20240525

# OpenResty image runs as root and uses 'nobody' for workers by default.
# Create an explicit 'nginx' user/group so the container can run unprivileged.
RUN groupadd -r -g 101 nginx \
    && useradd -r -u 101 -g 101 -s /sbin/nologin -M nginx

# Brotli is compiled as a dynamic module against the matching vanilla nginx core.
# OpenResty patches nginx but keeps module ABI compatible when built with --with-compat.
WORKDIR /usr/local/src
RUN apt-get update && apt-get install -y --no-install-recommends \
        libbrotli1 \
        logrotate \
        wget \
        ca-certificates \
        build-essential \
        libpcre3-dev \
        zlib1g-dev \
        libbrotli-dev \
        git \
    && git clone https://github.com/google/ngx_brotli.git \
    && git -C ngx_brotli checkout --quiet ${NGX_BROTLI_COMMIT} \
    && git -C ngx_brotli submodule update --init --recursive \
    && wget -q https://nginx.org/download/nginx-${NGINX_CORE_VERSION}.tar.gz \
    && echo "${NGINX_CORE_SHA256}  nginx-${NGINX_CORE_VERSION}.tar.gz" | sha256sum -c - \
    && tar -xzf nginx-${NGINX_CORE_VERSION}.tar.gz \
    && mv nginx-${NGINX_CORE_VERSION} nginx-src \
    && cd nginx-src \
    && ./configure --with-compat --add-dynamic-module=../ngx_brotli \
    && make modules \
    && mkdir -p /usr/local/openresty/nginx/modules \
    && cp objs/ngx_http_brotli_filter_module.so objs/ngx_http_brotli_static_module.so /usr/local/openresty/nginx/modules/ \
    && cd / \
    && rm -rf /usr/local/src/* \
    && opm get knyar/nginx-lua-prometheus=${PROMETHEUS_LUA_VERSION} \
    && apt-get purge -y build-essential libpcre3-dev zlib1g-dev libbrotli-dev git \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /

# Gateway runtime: the image owns nginx.conf, the user owns /etc/nginx/conf.d.
COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY snippets/ /usr/local/openresty/nginx/conf/snippets/
COPY examples/ /usr/local/openresty/nginx/conf/examples/
COPY lualib/gateway/ /usr/local/openresty/site/lualib/gateway/
COPY conf.d/ /etc/nginx/conf.d/

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# The nginx prefix, modules, Lua code and nginx.conf stay root-owned so a
# compromised worker cannot persist by rewriting them. The runtime user only
# writes logs, buffers, the logrotate config and conf/gateway (rendered
# fragments plus the published config snapshots that conf/routes points at).
RUN rm -f /etc/nginx/conf.d/default.conf \
    && mkdir -p /var/log/nginx /var/cache/nginx /usr/local/openresty/nginx/conf/gateway \
    && ln -sfn gateway/current /usr/local/openresty/nginx/conf/routes \
    && chown -R nginx:nginx \
        /var/log/nginx \
        /var/cache/nginx \
        /etc/logrotate.d \
        /usr/local/openresty/nginx/conf/gateway

# 80/443 work for the non-root user because Docker sets
# net.ipv4.ip_unprivileged_port_start=0 inside the container's network
# namespace (not with --network host; on Kubernetes declare that sysctl).
EXPOSE 80 443 8081

# Liveness lives on the internal status port so it never depends on user routes.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -q -O /dev/null http://127.0.0.1:8081/healthz || exit 1

USER nginx

STOPSIGNAL SIGQUIT

ENTRYPOINT ["/entrypoint.sh"]

FROM openresty/openresty:1.31.1.1-bookworm-fat

LABEL maintainer="Bismarck Villca Soliz <bismarck.villca@gmail.com>"

# Must match the nginx core bundled by the OpenResty tag above (<core>.<resty-rev>).
ARG NGINX_CORE_VERSION=1.31.1
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
    && git clone --recurse-submodules -j8 https://github.com/google/ngx_brotli.git \
    && wget -q https://nginx.org/download/nginx-${NGINX_CORE_VERSION}.tar.gz \
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

# Hand ownership of everything the gateway writes at runtime to the nginx user.
RUN rm -f /etc/nginx/conf.d/default.conf \
    && mkdir -p /var/log/nginx /var/cache/nginx /usr/local/openresty/nginx/conf/gateway \
    && chown -R nginx:nginx \
        /var/log/nginx \
        /var/cache/nginx \
        /etc/nginx/conf.d \
        /etc/logrotate.d \
        /usr/local/openresty/nginx

EXPOSE 8080 8081

# Liveness lives on the internal status port so it never depends on user routes.
HEALTHCHECK --interval=30s --timeout=5s CMD wget -q -O /dev/null http://127.0.0.1:8081/healthz || exit 1

USER nginx

STOPSIGNAL SIGQUIT

ENTRYPOINT ["/entrypoint.sh"]

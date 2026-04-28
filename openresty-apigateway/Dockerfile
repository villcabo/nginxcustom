FROM openresty/openresty:1.29.2.3-bookworm-fat

LABEL maintainer="Bismarck Villca Soliz <bismarck.villca@gmail.com>"

ARG NGINX_CORE_VERSION=1.29.2

# OpenResty image runs as root and uses 'nobody' for workers by default.
# Create an explicit 'nginx' user/group so the container can run unprivileged.
RUN groupadd -r -g 101 nginx \
    && useradd -r -u 101 -g 101 -s /sbin/nologin -M nginx

# Install runtime + build deps in one layer (build deps purged at the end)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libmaxminddb0 \
    libbrotli1 \
    libpcre3 \
    zlib1g \
    logrotate \
    wget \
    ca-certificates \
    build-essential \
    libpcre3-dev \
    zlib1g-dev \
    libmaxminddb-dev \
    libbrotli-dev \
    git \
    unzip

# Compile GeoIP2 + Brotli as dynamic modules against matching nginx core version.
# OpenResty patches nginx but keeps module ABI compatible when built with --with-compat.
WORKDIR /usr/local/src
RUN wget -q https://github.com/leev/ngx_http_geoip2_module/archive/refs/heads/master.zip \
    && unzip -q master.zip \
    && mv ngx_http_geoip2_module-master ngx_http_geoip2_module \
    && rm master.zip \
    && git clone --recurse-submodules -j8 https://github.com/google/ngx_brotli.git \
    && wget -q https://nginx.org/download/nginx-${NGINX_CORE_VERSION}.tar.gz \
    && tar -xzf nginx-${NGINX_CORE_VERSION}.tar.gz \
    && mv nginx-${NGINX_CORE_VERSION} nginx-src \
    && rm nginx-${NGINX_CORE_VERSION}.tar.gz \
    && cd nginx-src \
    && ./configure --with-compat \
        --add-dynamic-module=../ngx_http_geoip2_module \
        --add-dynamic-module=../ngx_brotli \
    && make modules \
    && mkdir -p /usr/local/openresty/nginx/modules \
    && cp objs/ngx_http_geoip2_module.so /usr/local/openresty/nginx/modules/ \
    && cp objs/ngx_http_brotli_filter_module.so /usr/local/openresty/nginx/modules/ \
    && cp objs/ngx_http_brotli_static_module.so /usr/local/openresty/nginx/modules/ \
    && cd / \
    && rm -rf /usr/local/src/* \
    && apt-get purge -y build-essential libpcre3-dev zlib1g-dev libmaxminddb-dev libbrotli-dev git unzip \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy logrotate configuration
COPY logrotate.conf /etc/logrotate.d/nginx
RUN chmod 0644 /etc/logrotate.d/nginx

# Copy api gateway example config (not active by default — admin enables it)
COPY apigateway-example.conf /usr/local/openresty/nginx/conf/conf.d/apigateway-example.conf

# Copy entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Healthcheck against :8080
HEALTHCHECK --interval=30s --timeout=5s CMD wget -q -O /dev/null http://localhost:8080/ || exit 1

# Configure for non-root execution: rewrite default vhost to :8080,
# strip user directive, move pid to /tmp, hand ownership to nginx user.
RUN sed -i 's/listen       80;/listen       8080;/g' /etc/nginx/conf.d/default.conf \
    && sed -i 's/^user .*/#user nginx;/g; s|pid .*|pid /tmp/nginx.pid;|g' /usr/local/openresty/nginx/conf/nginx.conf \
    && mkdir -p /var/cache/nginx /var/log/nginx /usr/local/openresty/nginx/logs \
    && chown -R nginx:nginx \
        /var/cache/nginx \
        /var/log/nginx \
        /etc/nginx/conf.d \
        /etc/logrotate.d \
        /usr/local/openresty/nginx \
        /tmp \
    && touch /tmp/nginx.pid \
    && chown nginx:nginx /tmp/nginx.pid

USER nginx

STOPSIGNAL SIGQUIT

ENTRYPOINT ["/entrypoint.sh"]

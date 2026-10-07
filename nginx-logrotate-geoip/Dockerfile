FROM nginx:1.31.6-trixie

LABEL maintainer="Bismarck Villca Soliz <bismarck.villca@gmail.com>"

# Install runtime dependencies and build tools in one layer
RUN apt-get update && apt-get upgrade -y && apt-get install -y \
    # Runtime dependencies (kept in final image)
    libmaxminddb0 \
    libbrotli1 \
    libpcre2-8-0 \
    zlib1g \
    logrotate \
    wget \
    # Build dependencies (will be removed)
    build-essential \
    libpcre2-dev \
    zlib1g-dev \
    libmaxminddb-dev \
    libbrotli-dev \
    git \
    unzip

# Download, build modules, and clean up in a single layer to reduce image size
WORKDIR /usr/local/src
RUN wget https://github.com/leev/ngx_http_geoip2_module/archive/refs/heads/master.zip \
    && unzip master.zip \
    && mv ngx_http_geoip2_module-master ngx_http_geoip2_module \
    && rm master.zip \
    && git clone --recurse-submodules -j8 https://github.com/google/ngx_brotli.git \
    && wget https://nginx.org/download/nginx-1.31.6.tar.gz \
    && tar -xzf nginx-1.31.6.tar.gz \
    && mv nginx-1.31.6 nginx-src \
    && rm nginx-1.31.6.tar.gz \
    && cd nginx-src \
    && ./configure --with-compat \
        --add-dynamic-module=../ngx_http_geoip2_module \
        --add-dynamic-module=../ngx_brotli \
    && make modules \
    && cp objs/ngx_http_geoip2_module.so /etc/nginx/modules/ \
    && cp objs/ngx_http_brotli_filter_module.so /etc/nginx/modules/ \
    && cp objs/ngx_http_brotli_static_module.so /etc/nginx/modules/ \
    && cd / \
    && rm -rf /usr/local/src/* \
    && apt-get purge -y build-essential libpcre2-dev zlib1g-dev libbrotli-dev git unzip \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy logrotate configuration
COPY logrotate.conf /etc/logrotate.d/nginx
RUN chmod 0644 /etc/logrotate.d/nginx

# Reference config for the dynamic modules, kept outside conf.d so it is never auto-included
COPY nginx-modules.conf /etc/nginx/examples/modules.conf

# Copy entrypoint.sh
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Add Healthcheck
HEALTHCHECK --interval=30s --timeout=5s CMD wget -q -O /dev/null http://127.0.0.1:8080/ || exit 1

# Configure Nginx for non-root execution
RUN sed -i 's/listen       80;/listen       8080;/g' /etc/nginx/conf.d/default.conf && \
    sed -i 's/user  nginx;//g' /etc/nginx/nginx.conf && \
    sed -i 's|^pid .*|pid        /tmp/nginx.pid;|' /etc/nginx/nginx.conf && \
    chown -R nginx:nginx /var/cache/nginx /var/log/nginx /etc/nginx/conf.d /etc/logrotate.d && \
    touch /var/run/nginx.pid && \
    chown -R nginx:nginx /var/run/nginx.pid /tmp

USER nginx

ENTRYPOINT [ "/entrypoint.sh" ]

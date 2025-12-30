FROM nginx:1.29.0-bookworm

LABEL maintainer="Bismarck Villca Soliz <bismarck.villca@gmail.com>"

# Install runtime dependencies and build tools in one layer
RUN apt-get update && apt-get upgrade -y && apt-get install -y \
    # Runtime dependencies (kept in final image)
    libmaxminddb0 \
    libbrotli1 \
    libpcre3 \
    zlib1g \
    logrotate \
    # Build dependencies (will be removed)
    build-essential \
    libpcre3-dev \
    zlib1g-dev \
    libmaxminddb-dev \
    libbrotli-dev \
    git \
    wget \
    unzip

# Download, build modules, and clean up in a single layer to reduce image size
WORKDIR /usr/local/src
RUN wget https://github.com/leev/ngx_http_geoip2_module/archive/refs/heads/master.zip \
    && unzip master.zip \
    && mv ngx_http_geoip2_module-master ngx_http_geoip2_module \
    && rm master.zip \
    && git clone --recurse-submodules -j8 https://github.com/google/ngx_brotli.git \
    && wget https://nginx.org/download/nginx-1.29.0.tar.gz \
    && tar -xzf nginx-1.29.0.tar.gz \
    && mv nginx-1.29.0 nginx-src \
    && rm nginx-1.29.0.tar.gz \
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
    && apt-get purge -y build-essential libpcre3-dev zlib1g-dev libbrotli-dev git wget unzip \
    && apt-get autoremove -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy logrotate configuration
COPY logrotate.conf /etc/logrotate.d/nginx
RUN chmod 0644 /etc/logrotate.d/nginx

# Copy example nginx configuration with modules
COPY nginx-modules.conf /etc/nginx/conf.d/modules-example.conf

# Copy entrypoint.sh
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Setup cron for logrotate every 6 hours
RUN echo "0 */6 * * * root /usr/sbin/logrotate -vf /etc/logrotate.d/nginx" >> /etc/crontab

# Create log directory for cron
RUN mkdir -p /var/log/cron

# Ensure cron service can run
RUN touch /var/log/cron.log

ENTRYPOINT [ "/entrypoint.sh" ]

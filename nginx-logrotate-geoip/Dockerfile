FROM nginx:1.29-bookworm

LABEL maintainer="Bismarck Villca Soliz <bismarck.villca@gmail.com>"

# Install required dependencies
RUN apt-get update && apt-get upgrade -y && apt-get install -y \
    build-essential \
    libpcre3 libpcre3-dev \
    zlib1g zlib1g-dev \
    libmaxminddb-dev \
    logrotate \
    wget \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Download and build the GeoIP2 module
WORKDIR /usr/local/src
RUN wget https://github.com/leev/ngx_http_geoip2_module/archive/refs/heads/master.zip \
    && unzip master.zip \
    && mv ngx_http_geoip2_module-master ngx_http_geoip2_module

# Download Nginx source code for compilation
WORKDIR /usr/local/src
RUN wget https://nginx.org/download/nginx-1.29.0.tar.gz \
    && tar -xvzf nginx-1.29.0.tar.gz \
    && mv nginx-1.29.0 nginx-src

# Build GeoIP2 modules with Nginx
WORKDIR /usr/local/src/nginx-src
RUN ./configure --with-compat --add-dynamic-module=../ngx_http_geoip2_module \
    && make modules \
    && cp objs/ngx_http_geoip2_module.so /etc/nginx/modules/

# Clean up sources
WORKDIR /
RUN rm -rf /usr/local/src/*

# Copy logrotate configuration
COPY logrotate.conf /etc/logrotate.d/nginx
RUN chmod 0644 /etc/logrotate.d/nginx

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

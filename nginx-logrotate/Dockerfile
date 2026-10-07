FROM nginx:1.31-alpine

LABEL maintainer="Bismarck Villca Soliz <bismarck.villca@gmail.com>"

# Install dependencies
RUN apk add --no-cache logrotate

# Copy logrotate configuration
COPY logrotate.conf /etc/logrotate.d/nginx
RUN chmod 0644 /etc/logrotate.d/nginx

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

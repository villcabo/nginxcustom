FROM nginx:1.31-alpine

LABEL maintainer="Bismarck Villca Soliz <bismarck.villca@gmail.com>"

# Install dependencies
RUN apk add --no-cache logrotate

# Copy entrypoint.sh
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Add Healthcheck
# The non-root user can bind :80 because Docker sets
# net.ipv4.ip_unprivileged_port_start=0 in the container's network namespace.
HEALTHCHECK --interval=30s --timeout=5s CMD wget -q -O /dev/null http://127.0.0.1/ || exit 1

# Configure Nginx for non-root execution
RUN sed -i 's/user  nginx;//g' /etc/nginx/nginx.conf && \
    sed -i 's|^pid .*|pid        /tmp/nginx.pid;|' /etc/nginx/nginx.conf && \
    chown -R nginx:nginx /var/cache/nginx /var/log/nginx /etc/nginx/conf.d /etc/logrotate.d && \
    touch /var/run/nginx.pid && \
    chown -R nginx:nginx /var/run/nginx.pid /tmp

USER nginx

ENTRYPOINT [ "/entrypoint.sh" ]

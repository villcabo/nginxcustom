FROM nginx:1.26-alpine-slim

LABEL maintainer="Bismarck Villca Soliz <bismarck.villca@gmail.com>"

# Install dependencies
RUN apk update && apk add --no-cache logrotate nginx-mod-http-geoip2 nginx-mod-stream-geoip2

# Copy logrotate configuration
COPY logrotate.conf /etc/logrotate.d/nginx
RUN chmod 0644 /etc/logrotate.d/nginx

# Copy entrypoint.sh
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Cron to run logrotate every 6 hours
RUN echo "0 */6 * * * /usr/sbin/logrotate -vf /etc/logrotate.d/nginx" > /etc/crontabs/root

# Create log directory for cron
RUN mkdir -p /var/log/cron

ENTRYPOINT [ "/entrypoint.sh" ]

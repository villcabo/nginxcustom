#!/bin/sh

set -e

echo "---------------------------------------------------------------"
echo "$(nginx -V)"
echo "---------------------------------------------------------------"

echo "Validating Nginx configuration..."
if nginx -t; then
    echo "Nginx config is valid."
else
    echo "Nginx config has errors. Exiting..."
    exit 1
fi

# Apply runtime overrides to logrotate config
LOGROTATE_MAXSIZE="${LOGROTATE_MAXSIZE:-1G}"
sed -i "s|^[[:space:]]*maxsize .*|    maxsize ${LOGROTATE_MAXSIZE}|" /etc/logrotate.d/nginx

# Start background logrotate loop
LOGROTATE_DELAY_SECONDS="${LOGROTATE_DELAY_SECONDS:-3600}"
echo "Starting logrotate loop (every ${LOGROTATE_DELAY_SECONDS}s, maxsize=${LOGROTATE_MAXSIZE})..."
(
  while true; do
    sleep "$LOGROTATE_DELAY_SECONDS"
    /usr/sbin/logrotate -vf /etc/logrotate.d/nginx
  done
) &

# Start Nginx in the foreground
echo "Starting (Nginx + LogRotate) Alpine..."
exec nginx -g "daemon off;"

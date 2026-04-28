#!/bin/bash

set -e

echo "---------------------------------------------------------------"
echo "$(nginx -V)"
echo "---------------------------------------------------------------"

# Check if modules are available
echo "Checking available dynamic modules:"
if [ -f "/etc/nginx/modules/ngx_http_geoip2_module.so" ]; then
    echo "✓ GeoIP2 module: AVAILABLE"
else
    echo "✗ GeoIP2 module: NOT FOUND"
fi

if [ -f "/etc/nginx/modules/ngx_http_brotli_filter_module.so" ]; then
    echo "✓ Brotli Filter module: AVAILABLE"
else
    echo "✗ Brotli Filter module: NOT FOUND"
fi

if [ -f "/etc/nginx/modules/ngx_http_brotli_static_module.so" ]; then
    echo "✓ Brotli Static module: AVAILABLE"
else
    echo "✗ Brotli Static module: NOT FOUND"
fi

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

# Function to handle shutdown gracefully
cleanup() {
    echo "Shutting down services..."
    nginx -s quit
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT

# Start Nginx in the foreground
echo "Starting (Nginx + LogRotate + GeoIP + Brotli) in Debian Bookworm..."
nginx -g "daemon off;" &

# Keep the script running and wait for signals
wait $!

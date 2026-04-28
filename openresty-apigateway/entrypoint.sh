#!/bin/bash

set -e

echo "---------------------------------------------------------------"
openresty -V 2>&1
echo "---------------------------------------------------------------"

echo "Checking available dynamic modules:"
for mod in ngx_http_geoip2_module ngx_http_brotli_filter_module ngx_http_brotli_static_module; do
    if [ -f "/usr/local/openresty/nginx/modules/${mod}.so" ]; then
        echo "  AVAILABLE  ${mod}.so"
    else
        echo "  MISSING    ${mod}.so"
    fi
done

echo "---------------------------------------------------------------"

# Apply runtime overrides to logrotate config
LOGROTATE_MAXSIZE="${LOGROTATE_MAXSIZE:-1G}"
sed -i "s|^[[:space:]]*maxsize .*|    maxsize ${LOGROTATE_MAXSIZE}|" /etc/logrotate.d/nginx

echo "Validating OpenResty configuration..."
if openresty -t; then
    echo "Config is valid."
else
    echo "Config has errors. Exiting..."
    exit 1
fi

# Background logrotate loop
LOGROTATE_DELAY_SECONDS="${LOGROTATE_DELAY_SECONDS:-3600}"
echo "Starting logrotate loop (every ${LOGROTATE_DELAY_SECONDS}s, maxsize=${LOGROTATE_MAXSIZE})..."
(
  while true; do
    sleep "$LOGROTATE_DELAY_SECONDS"
    /usr/sbin/logrotate -vf /etc/logrotate.d/nginx
  done
) &

cleanup() {
    echo "Shutting down OpenResty..."
    openresty -s quit
    exit 0
}

trap cleanup SIGTERM SIGINT SIGQUIT

echo "Starting OpenResty (Nginx + Lua + LogRotate + GeoIP2 + Brotli) on Bookworm..."
openresty -g "daemon off;" &

wait $!

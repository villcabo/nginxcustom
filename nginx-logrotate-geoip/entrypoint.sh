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

# Start cron daemon (Debian uses 'cron' instead of 'crond')
echo "Starting cron daemon..."
service cron start

# Function to handle shutdown gracefully
cleanup() {
    echo "Shutting down services..."
    service cron stop
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

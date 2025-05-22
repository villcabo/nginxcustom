#!/bin/sh

set -e

echo "🔍 Validating Nginx configuration..."
if nginx -t; then
    echo "✅ Nginx config is valid."
else
    echo "❌ Nginx config has errors. Exiting..."
    exit 1
fi

# Start cron daemon
echo "🕒 Starting cron daemon..."
crond -L /var/log/cron.log

# Start Nginx in the foreground
echo "🚀 Starting Nginx + LogRotate + GeoIP..."
nginx -g "daemon off;"

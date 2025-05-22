#!/bin/sh

set -e

echo "🔍 Validating NGINX configuration..."
if nginx -t; then
    echo "✅ NGINX config is valid."
else
    echo "❌ NGINX config has errors. Exiting..."
    exit 1
fi

# Start cron daemon
echo "🕒 Starting cron daemon..."
crond -L /var/log/cron.log

# Start NGINX in the foreground
echo "🚀 Starting NGINX..."
nginx -g "daemon off;"

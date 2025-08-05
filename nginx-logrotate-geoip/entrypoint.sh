#!/bin/bash

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
echo "Starting (Nginx + LogRotate + GeoIP) in Debian Bookworm..."
nginx -g "daemon off;" &

# Keep the script running and wait for signals
wait $!

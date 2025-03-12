#!/bin/sh

# Create the crontab file for logrotate
echo "0 0 * * * /usr/sbin/logrotate /etc/logrotate.d/nginx" > /etc/crontabs/root

# Start crond
crond

# Start Nginx
nginx -g "daemon off;"

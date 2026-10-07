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

LOGROTATE_FREQUENCY="${LOGROTATE_FREQUENCY:-daily}"
LOGROTATE_MAXSIZE="${LOGROTATE_MAXSIZE-1G}"
LOGROTATE_ROTATE="${LOGROTATE_ROTATE:-180}"
LOGROTATE_COMPRESS="${LOGROTATE_COMPRESS:-true}"
LOGROTATE_DELAY_SECONDS="${LOGROTATE_DELAY_SECONDS:-300}"
LOGROTATE_STATE_FILE="${LOGROTATE_STATE_FILE:-/var/log/nginx/.logrotate.status}"
LOGROTATE_CONF=/etc/logrotate.d/nginx

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

# Rotation triggers:
#   hourly|daily|weekly|monthly  rotate on that schedule, and earlier whenever a
#                                file exceeds LOGROTATE_MAXSIZE (empty = never early)
#   size                         rotate only when a file exceeds LOGROTATE_MAXSIZE
render_logrotate_conf() {
    case "$LOGROTATE_FREQUENCY" in
        hourly|daily|weekly|monthly)
            trigger="    $LOGROTATE_FREQUENCY"
            if [ -n "$LOGROTATE_MAXSIZE" ]; then
                trigger="$trigger
    maxsize $LOGROTATE_MAXSIZE"
            fi
            ;;
        size)
            [ -n "$LOGROTATE_MAXSIZE" ] || fail "LOGROTATE_FREQUENCY=size requires LOGROTATE_MAXSIZE"
            trigger="    size $LOGROTATE_MAXSIZE"
            ;;
        *)
            fail "LOGROTATE_FREQUENCY must be hourly, daily, weekly, monthly or size (got '$LOGROTATE_FREQUENCY')"
            ;;
    esac
    if [ -n "$LOGROTATE_MAXSIZE" ] && ! echo "$LOGROTATE_MAXSIZE" | grep -Eq '^[0-9]+[kMG]?$'; then
        fail "LOGROTATE_MAXSIZE must look like 500k, 100M or 1G (got '$LOGROTATE_MAXSIZE')"
    fi
    echo "$LOGROTATE_ROTATE" | grep -Eq '^[0-9]+$' || fail "LOGROTATE_ROTATE must be an integer"

    compression="    nocompress"
    if [ "$LOGROTATE_COMPRESS" = "true" ]; then
        compression="    compress
    delaycompress"
    fi

    cat > "$LOGROTATE_CONF" <<EOF
/var/log/nginx/*.log /var/log/nginx/*/*.log /var/log/nginx/*.json /var/log/nginx/*/*.json {
$trigger
    rotate $LOGROTATE_ROTATE
$compression
    missingok
    notifempty
    dateext
    dateformat -%Y%m%d-%s
    create 0640
    sharedscripts
    postrotate
        [ -f /tmp/nginx.pid ] && kill -USR1 \$(cat /tmp/nginx.pid) || true
    endscript
}
EOF
    echo "logrotate: frequency=$LOGROTATE_FREQUENCY maxsize=${LOGROTATE_MAXSIZE:-<none>} keep=$LOGROTATE_ROTATE compress=$LOGROTATE_COMPRESS check_every=${LOGROTATE_DELAY_SECONDS}s"
}

# logrotate decides from its state file whether a rotation is due, so the loop
# only needs to check often enough for the smallest trigger. Never pass -f:
# forcing would rotate on every check regardless of frequency or size.
render_logrotate_conf
(
  while sleep "$LOGROTATE_DELAY_SECONDS"; do
    /usr/sbin/logrotate -s "$LOGROTATE_STATE_FILE" "$LOGROTATE_CONF" || echo "logrotate exited with an error"
  done
) &

# Start Nginx in the foreground
echo "Starting (Nginx + LogRotate) Alpine..."
exec nginx -g "daemon off;"

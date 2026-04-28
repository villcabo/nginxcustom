#!/usr/bin/env bash
# Continuous probe for the apigateway test harness.
# Run AFTER `docker compose up -d`. In a second terminal, kill a backend with
# `docker compose stop backend1` (or `restart`) and observe the curl loop.

set -u

GATEWAY="${GATEWAY:-http://localhost:8080}"
INTERVAL="${INTERVAL:-1}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-90}"

color() { printf "\033[%sm%s\033[0m" "$1" "$2"; }
red()    { color "1;31" "$1"; }
green()  { color "1;32" "$1"; }
yellow() { color "1;33" "$1"; }
blue()   { color "1;34" "$1"; }
gray()   { color "0;90" "$1"; }

echo "$(blue "Gateway:") $GATEWAY"
echo "$(blue "Interval:") ${INTERVAL}s"
echo

# ---- Phase 1: wait for both backends to be UP via the gateway's status page.
echo "$(yellow "Waiting for both peers to be UP (timeout ${WAIT_TIMEOUT}s)...")"
deadline=$(( $(date +%s) + WAIT_TIMEOUT ))
while :; do
    status=$(curl -fsS "${GATEWAY}/healthcheck-status" 2>/dev/null || true)
    # Status page lists peers as "<ip>:<port> UP|DOWN" — peers are resolved
    # from hostname to IP by the healthchecker, so match on the trailing UP.
    up_count=$(echo "$status" | grep -cE ':[0-9]+[[:space:]]+UP([[:space:]]|$)' || true)
    if [[ "$up_count" -ge 2 ]]; then
        echo "$(green "Both peers UP. Status page:")"
        echo "$status" | sed 's/^/    /'
        break
    fi
    now=$(date +%s)
    if (( now >= deadline )); then
        echo "$(red "Timeout waiting for peers to be UP.") Last status:"
        echo "$status" | sed 's/^/    /'
        exit 1
    fi
    echo "  $(gray "$(date +%H:%M:%S) up=${up_count}/2, retrying...")"
    sleep 2
done

# ---- Phase 2: continuous probe loop.
echo
echo "$(yellow "Starting curl loop. Ctrl+C to stop.")"
echo "$(gray "Try in another terminal: docker compose stop backend1   # then start it again")"
echo

trap 'echo; echo "$(yellow "stopping.")"; exit 0' INT TERM

while :; do
    ts=$(date +%H:%M:%S)
    out=$(curl -sS -o /tmp/apigw-body.$$ -w "%{http_code} %{time_total}" "${GATEWAY}/" 2>&1) || rc=$? && rc=${rc:-0}
    body=$(cat /tmp/apigw-body.$$ 2>/dev/null || true)
    rm -f /tmp/apigw-body.$$

    code=$(echo "$out" | awk '{print $1}')
    t=$(echo "$out" | awk '{print $2}')

    case "$code" in
        2*) tag=$(green "HTTP $code") ;;
        5*) tag=$(red   "HTTP $code") ;;
         *) tag=$(yellow "HTTP $code") ;;
    esac

    # Pull "backend":"backendN" out of the body.
    who=$(echo "$body" | grep -oE '"backend":"[^"]+"' | head -1)
    echo "[$ts] ${tag} t=${t}s  ${who}  $(gray "$body")"

    sleep "$INTERVAL"
done

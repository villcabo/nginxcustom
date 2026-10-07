#!/usr/bin/env bash
# Automated acceptance tests for openresty-apigateway.
#
# Brings up the harness on a throwaway copy of conf.d, asserts the gateway
# contracts end to end, tears everything down and exits non-zero on any
# failure. Used by CI; run it locally the same way: ./test.sh

set -uo pipefail

cd "$(dirname "$0")"

GATEWAY=http://localhost:8080
STATUS=http://localhost:8081
WORK=$(mktemp -d)
export GATEWAY_CONF_DIR=$WORK/conf.d
export COMPOSE_PROJECT_NAME=apigw-test

passed=0
failed=0

pass() { passed=$((passed + 1)); echo "  PASS  $*"; }
fail() { failed=$((failed + 1)); echo "  FAIL  $*"; }
check() {
    local description=$1
    shift
    if "$@"; then pass "$description"; else fail "$description"; fi
}

# Polls a command until it succeeds or the timeout (seconds) expires.
eventually() {
    local timeout=$1 deadline
    shift
    deadline=$(( $(date +%s) + timeout ))
    until "$@"; do
        (( $(date +%s) >= deadline )) && return 1
        sleep 1
    done
}

cleanup() {
    echo
    echo "== teardown"
    docker compose logs gateway > "$WORK/gateway.log" 2>&1 || true
    if (( failed > 0 )); then
        echo "-- last gateway log lines --"
        tail -30 "$WORK/gateway.log"
    fi
    docker compose down -v --remove-orphans > /dev/null 2>&1
    rm -rf "$WORK"
}
trap cleanup EXIT

config_state() { curl -fsS "$STATUS/status/config" | grep -o '"state":"[a-z]*"' | cut -d'"' -f4; }
peers_up() { curl -fsS "$STATUS/status/upstreams" | awk -v u="Upstream $1" '$0 ~ u {f=1; next} /^Upstream/ {f=0} f && / UP$/ {n++} END {print n+0}'; }
pool_ready() { [ "$(peers_up backend_api)" -ge 2 ] && [ "$(peers_up scaled_api)" -ge 2 ]; }
state_is() { [ "$(config_state)" = "$1" ]; }
route_ok() { [ "$(curl -s -o /dev/null -w '%{http_code}' -H "Host: ${2:-localhost}" "$GATEWAY$1")" = "200" ]; }
distinct_hosts() { for _ in $(seq 1 "$2"); do curl -s "$GATEWAY$1" | grep -o '"host":"[^"]*"'; done | sort -u | wc -l; }

# The container runs as uid 101; the copy must be readable by it.
cp -r conf.d "$WORK/conf.d"
chmod 755 "$WORK" "$WORK/conf.d"
chmod 644 "$WORK"/conf.d/*

echo "== setup"
docker compose up -d --build --scale scaled=2 > "$WORK/up.log" 2>&1 || { cat "$WORK/up.log"; exit 1; }
if ! eventually 90 pool_ready; then
    fail "both pools reach 2 healthy peers"
    exit 1
fi
pass "both pools reach 2 healthy peers"

echo "== routing"
check "static pool balances across backend1 and backend2" \
    test "$(distinct_hosts / 10)" -eq 2
check "DNS pool balances across the scaled replicas" \
    test "$(distinct_hosts /scaled/ 10)" -eq 2

echo "== gateway-generated errors"
body=$(curl -s "$GATEWAY/missing")
check "404 has a JSON body with request_id" \
    grep -q '^{"error":"not_found","status":404,"request_id":"[0-9a-f]\{32\}"}$' <<< "$body"
codes=$(seq 40 | xargs -P 40 -I{} curl -s -o /dev/null -w '%{http_code}\n' "$GATEWAY/limited/")
check "rate limit rejects a burst with 429" grep -q '^429$' <<< "$codes"
body=$(head -c 11000000 /dev/zero | curl -s -X POST --data-binary @- "$GATEWAY/")
check "oversized body gets a JSON 413" grep -q '"error":"payload_too_large"' <<< "$body"

echo "== headers"
check "a valid X-Request-ID is propagated to the client" \
    grep -qi '^x-request-id: abc-123' <<< "$(curl -si -H 'X-Request-ID: abc-123' "$GATEWAY/")"
check "an invalid X-Request-ID is replaced" \
    bash -c "! curl -si -H 'X-Request-ID: bad id <script>' '$GATEWAY/' | grep -qi 'script'"
check "a spoofed X-Forwarded-For does not reach the backend" \
    bash -c "! curl -s -H 'X-Forwarded-For: 6.6.6.6' '$GATEWAY/' | grep -q '6.6.6.6'"
check "the Server header is not exposed" \
    bash -c "! curl -sI '$GATEWAY/' | grep -qi '^server:'"

echo "== metrics"
metrics=$(curl -s "$STATUS/metrics")
check "request counter is exported" grep -q '^gateway_http_requests_total{' <<< "$metrics"
check "config is reported valid" grep -q '^gateway_config_valid 1' <<< "$metrics"
check "peer health is exported" grep -q '^nginx_upstream_status_info{' <<< "$metrics"

echo "== failover"
( for _ in $(seq 1 60); do curl -s -o /dev/null -w '%{http_code}\n' "$GATEWAY/"; sleep 0.1; done ) > "$WORK/failover.txt" &
probe=$!
sleep 1
docker compose stop backend1 > /dev/null 2>&1
wait "$probe"
check "no client error while backend1 stops (60 requests)" \
    test "$(grep -vc '^200$' "$WORK/failover.txt")" -eq 0
docker compose start backend1 > /dev/null 2>&1
check "backend1 returns to the pool" eventually 30 bash -c "[ \"\$(curl -fsS $STATUS/status/upstreams | awk '/Upstream backend_api/{f=1;next} /^Upstream/{f=0} f && / UP\$/{n++} END{print n+0}')\" -ge 2 ]"

echo "== DNS discovery"
docker compose up -d --no-recreate --scale scaled=3 > /dev/null 2>&1
check "a third replica is discovered without reload" eventually 40 bash -c "[ \"\$(curl -fsS $STATUS/status/upstreams | awk '/Upstream scaled_api/{f=1;next} /^Upstream/{f=0} f && / UP\$/{n++} END{print n+0}')\" -ge 3 ]"

echo "== hot reload"
cat > "$GATEWAY_CONF_DIR/hot.conf" <<'EOF'
server {
    listen 80;
    server_name hot.test;
    location / { return 200 '{"hot":true}'; }
}
EOF
chmod 644 "$GATEWAY_CONF_DIR/hot.conf"
check "a new valid file is published" eventually 15 route_ok / hot.test
check "status reports valid" state_is valid

echo 'server { this_is_not_a_directive on; }' > "$GATEWAY_CONF_DIR/broken.conf"
chmod 644 "$GATEWAY_CONF_DIR/broken.conf"
check "an invalid file is rejected (status fallback)" eventually 15 state_is fallback
check "existing routes keep serving" route_ok /
check "the last published route keeps serving" route_ok / hot.test
check "metrics flag the fallback" bash -c "curl -s $STATUS/metrics | grep -q '^gateway_config_fallback 1'"
rm -f "$GATEWAY_CONF_DIR/broken.conf"
check "fixing the file publishes again" eventually 15 state_is valid

cp "$GATEWAY_CONF_DIR/healthchecks.json" "$WORK/healthchecks.json.bak"
echo '{"upstreams": ' > "$GATEWAY_CONF_DIR/healthchecks.json"
check "a broken healthchecks.json is rejected" eventually 15 state_is fallback
check "active health checks stay enabled" \
    bash -c "! curl -s $STATUS/status/upstreams | grep -q 'NO checkers'"
cp "$WORK/healthchecks.json.bak" "$GATEWAY_CONF_DIR/healthchecks.json"
check "restoring healthchecks.json publishes again" eventually 15 state_is valid
echo '{"upstreams": {"backend_api": {"interva": 2000}}}' > "$GATEWAY_CONF_DIR/healthchecks.json"
check "a typo in a health check option is rejected" eventually 15 state_is fallback
cp "$WORK/healthchecks.json.bak" "$GATEWAY_CONF_DIR/healthchecks.json"
check "healthchecks.json restored after the typo" eventually 15 state_is valid
echo '{"upstreams": {"ghost_api": {}}}' > "$GATEWAY_CONF_DIR/healthchecks.json"
check "a health check for an undeclared upstream is rejected" eventually 15 state_is fallback
cp "$WORK/healthchecks.json.bak" "$GATEWAY_CONF_DIR/healthchecks.json"
eventually 15 state_is valid

echo "== DNS-dependent upstreams"
cat > "$GATEWAY_CONF_DIR/ghost.conf" <<'EOF2'
upstream ghost_api {
    zone ghost_api 64k;
    server not-deployed-yet:8080 resolve;
}
server {
    listen 80;
    server_name ghost.test;
    location / { proxy_pass http://ghost_api; }
}
EOF2
chmod 644 "$GATEWAY_CONF_DIR/ghost.conf"
check "an upstream whose host does not exist yet is published (resolve)" eventually 15 state_is valid
check "other routes keep serving next to it" route_ok /
cat > "$GATEWAY_CONF_DIR/ghost.conf" <<'EOF2'
upstream ghost_api {
    zone ghost_api 64k;
    server backend1:8080;
}
EOF2
check "a hostname upstream without resolve is rejected" eventually 15 state_is fallback
rm -f "$GATEWAY_CONF_DIR/ghost.conf"
eventually 15 state_is valid

echo "== restart with an invalid conf.d"
echo 'server { this_is_not_a_directive on; }' > "$GATEWAY_CONF_DIR/broken.conf"
chmod 644 "$GATEWAY_CONF_DIR/broken.conf"
eventually 15 state_is fallback
docker compose restart gateway > /dev/null 2>&1
check "the gateway starts on the last known-good snapshot" eventually 30 route_ok /
check "status reports fallback after the restart" state_is fallback
rm -f "$GATEWAY_CONF_DIR/broken.conf"
check "fixing the file after the restart publishes again" eventually 15 state_is valid

echo "== graceful stop"
docker compose stop gateway > /dev/null 2>&1
check "the gateway exits cleanly on docker stop" \
    test "$(docker inspect -f '{{.State.ExitCode}}' apigw-gateway)" -eq 0

echo
echo "passed=$passed failed=$failed"
(( failed == 0 ))

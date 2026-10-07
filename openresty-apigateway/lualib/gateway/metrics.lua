-- Prometheus metrics for the gateway, exposed on the internal status port.
-- Labels use $server_name and the upstream name, never client-controlled
-- values like $host or $uri, to keep cardinality bounded.

local status = require("gateway.status")

local _M = {}

local prometheus
local requests
local request_duration
local upstream_duration
local connections
local config_valid
local config_fallback
local config_last_change

function _M.init()
    prometheus = require("prometheus").init("prometheus_metrics")

    requests = prometheus:counter(
        "gateway_http_requests_total",
        "Requests handled by the gateway",
        { "server", "upstream", "status" })
    request_duration = prometheus:histogram(
        "gateway_http_request_duration_seconds",
        "Total request time as seen by the client",
        { "server", "upstream" })
    upstream_duration = prometheus:histogram(
        "gateway_upstream_response_duration_seconds",
        "Time spent waiting on upstreams, summed across retries",
        { "upstream" })
    connections = prometheus:gauge(
        "gateway_connections",
        "Client connections by state",
        { "state" })
    config_valid = prometheus:gauge(
        "gateway_config_valid",
        "1 when the files in /etc/nginx/conf.d passed validation and are the ones being served")
    config_fallback = prometheus:gauge(
        "gateway_config_fallback",
        "1 when the gateway serves the last known-good config because conf.d is invalid")
    config_last_change = prometheus:gauge(
        "gateway_config_last_change_timestamp_seconds",
        "When conf.d was last validated, successfully or not")
end

-- $upstream_response_time lists one value per attempt ("0.010, 0.020"), per
-- internal redirect ("0.010 : 0.020"), and "-" for an attempt that never got
-- a response. Returns nil when there is no measured time at all, so failed
-- connections do not drag the histogram towards zero.
local function total_upstream_time(value)
    local total, measured = 0, false
    for seconds in value:gmatch("%d+%.?%d*") do
        total = total + tonumber(seconds)
        measured = true
    end
    return measured and total or nil
end

function _M.log()
    if not prometheus then
        return
    end

    local var = ngx.var
    local server = var.server_name or ""
    local upstream = var.proxy_host or ""

    requests:inc(1, { server, upstream, var.status })
    request_duration:observe(tonumber(var.request_time) or 0, { server, upstream })

    local upstream_time = var.upstream_response_time
    if upstream_time then
        local total = total_upstream_time(upstream_time)
        if total then
            upstream_duration:observe(total, { upstream })
        end
    end
end

function _M.collect()
    if not prometheus then
        ngx.status = ngx.HTTP_SERVICE_UNAVAILABLE
        ngx.say("metrics not initialised in this worker, see error.log")
        return
    end

    local var = ngx.var
    connections:set(tonumber(var.connections_active) or 0, { "active" })
    connections:set(tonumber(var.connections_reading) or 0, { "reading" })
    connections:set(tonumber(var.connections_writing) or 0, { "writing" })
    connections:set(tonumber(var.connections_waiting) or 0, { "waiting" })

    local config = status.read()
    config_valid:set(config.state == "valid" and 1 or 0)
    config_fallback:set(config.state == "fallback" and 1 or 0)
    config_last_change:set(tonumber(config.checked_at) or 0)

    prometheus:collect()
    ngx.print(require("resty.upstream.healthcheck").prometheus_status_page())
end

return _M

-- Prometheus metrics for the gateway, exposed on the internal status port.
-- Labels use $server_name and the upstream name, never client-controlled
-- values like $host or $uri, to keep cardinality bounded.

local _M = {}

local prometheus
local requests
local request_duration
local upstream_duration
local connections

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
end

-- $upstream_response_time lists one value per attempt ("0.010, 0.020") and
-- per internal redirect ("0.010 : 0.020").
local function total_upstream_time(value)
    local total = 0
    for seconds in value:gmatch("[%d%.]+") do
        total = total + (tonumber(seconds) or 0)
    end
    return total
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
        upstream_duration:observe(total_upstream_time(upstream_time), { upstream })
    end
end

function _M.collect()
    local var = ngx.var
    connections:set(tonumber(var.connections_active) or 0, { "active" })
    connections:set(tonumber(var.connections_reading) or 0, { "reading" })
    connections:set(tonumber(var.connections_writing) or 0, { "writing" })
    connections:set(tonumber(var.connections_waiting) or 0, { "waiting" })

    prometheus:collect()
    ngx.print(require("resty.upstream.healthcheck").prometheus_status_page())
end

return _M

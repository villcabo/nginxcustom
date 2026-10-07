-- Renders a JSON body for errors produced by the gateway itself.

local cjson = require("cjson.safe")

local _M = {}

local CODES = {
    [400] = "bad_request",
    [401] = "unauthorized",
    [403] = "forbidden",
    [404] = "not_found",
    [405] = "method_not_allowed",
    [408] = "request_timeout",
    [413] = "payload_too_large",
    [429] = "too_many_requests",
    [500] = "internal_error",
    [502] = "bad_gateway",
    [503] = "service_unavailable",
    [504] = "gateway_timeout",
}

-- Keys are written in a fixed order (cjson does not keep one) so clients and
-- log searches see the same shape every time.
function _M.render()
    local status = ngx.status
    ngx.header["Content-Type"] = "application/json"
    ngx.say(string.format('{"error":%s,"status":%d,"request_id":%s}',
        cjson.encode(CODES[status] or "error"),
        status,
        cjson.encode(ngx.var.gateway_request_id or "")))
end

return _M

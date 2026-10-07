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

function _M.render()
    local status = ngx.status
    ngx.header["Content-Type"] = "application/json"
    ngx.say(cjson.encode({
        error = CODES[status] or "error",
        status = status,
        request_id = ngx.var.gateway_request_id,
    }))
end

return _M

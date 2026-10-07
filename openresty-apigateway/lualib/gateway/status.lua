-- Reads the config status the entrypoint writes after every publish attempt.

local cjson = require("cjson.safe")

local _M = {}

local STATUS_FILE = "/usr/local/openresty/nginx/conf/gateway/status.json"

function _M.read_raw()
    local file = io.open(STATUS_FILE, "r")
    if not file then
        return '{"state":"unknown"}'
    end
    local body = file:read("*a")
    file:close()
    return body
end

function _M.read()
    return cjson.decode(_M.read_raw()) or { state = "unknown" }
end

return _M

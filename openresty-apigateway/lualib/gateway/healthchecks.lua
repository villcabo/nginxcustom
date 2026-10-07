-- Spawns lua-resty-upstream-healthcheck checkers from a declarative JSON file,
-- so active health checks are configured like routes: by editing a file.
--
-- File format:
--   {
--     "defaults":  { "path": "/health", "interval": 2000, ... },
--     "upstreams": { "<upstream name>": { "path": "/ready", ... } }
--   }
-- Any spawn_checker option is accepted per upstream; "path" and "host" build
-- the probe request unless a raw "http_req" is given.

local cjson = require("cjson.safe")
local hc = require("resty.upstream.healthcheck")

local _M = {}

local BUILTIN_DEFAULTS = {
    type = "http",
    path = "/health",
    interval = 2000,
    timeout = 1000,
    fall = 2,
    rise = 2,
    valid_statuses = { 200, 204 },
    concurrency = 10,
}

local function read_file(path)
    local file = io.open(path, "r")
    if not file then
        return nil
    end
    local body = file:read("*a")
    file:close()
    return body
end

local function merge(...)
    local result = {}
    for _, source in ipairs({ ... }) do
        for key, value in pairs(source) do
            result[key] = value
        end
    end
    return result
end

local function checker_options(upstream, defaults, spec)
    local opts = merge(BUILTIN_DEFAULTS, defaults, spec)
    opts.shm = "healthcheck"
    opts.upstream = upstream
    if not opts.http_req then
        opts.http_req = string.format(
            "GET %s HTTP/1.0\r\nHost: %s\r\nUser-Agent: openresty-apigateway-healthcheck\r\n\r\n",
            opts.path, opts.host or upstream)
    end
    opts.path = nil
    opts.host = nil
    return opts
end

function _M.spawn(path)
    local first_worker = ngx.worker.id() == 0

    local body = read_file(path)
    if not body then
        if first_worker then
            ngx.log(ngx.NOTICE, "healthchecks: ", path, " not found, active health checks disabled")
        end
        return
    end

    local config, err = cjson.decode(body)
    if type(config) ~= "table" or type(config.upstreams) ~= "table" then
        ngx.log(ngx.ERR, "healthchecks: invalid ", path, ": ", err or "missing \"upstreams\" object")
        return
    end

    local defaults = type(config.defaults) == "table" and config.defaults or {}
    for upstream, spec in pairs(config.upstreams) do
        local ok, spawn_err = hc.spawn_checker(checker_options(upstream, defaults, spec))
        if not ok then
            ngx.log(ngx.ERR, "healthchecks: upstream \"", upstream, "\": ", spawn_err)
        elseif first_worker then
            ngx.log(ngx.NOTICE, "healthchecks: active checks enabled for upstream \"", upstream, "\"")
        end
    end
end

return _M

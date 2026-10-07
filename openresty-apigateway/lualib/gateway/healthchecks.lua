-- Active health checks declared in a JSON file, so they are configured like
-- routes: by editing a file.
--
-- File format:
--   {
--     "defaults":  { "path": "/health", "interval": 2000, ... },
--     "upstreams": { "<upstream name>": { "path": "/ready", ... } }
--   }
--
-- load() is run by gateway.validate before a config is published, so a
-- broken file is rejected like a broken *.conf instead of silently disabling
-- the checks after a reload.

local cjson = require("cjson.safe")
local hc = require("resty.upstream.healthcheck")

local _M = {}

_M.BUILTIN_DEFAULTS = {
    type = "http",
    path = "/health",
    interval = 2000,
    timeout = 1000,
    fall = 2,
    rise = 2,
    valid_statuses = { 200, 204 },
    concurrency = 10,
}

local function positive_integer(value)
    return type(value) == "number" and value >= 1 and value == math.floor(value)
end

local OPTION_CHECKS = {
    type = function(v) return v == "http" or v == "https", 'must be "http" or "https"' end,
    path = function(v) return type(v) == "string" and v:sub(1, 1) == "/", 'must be a string starting with "/"' end,
    host = function(v) return type(v) == "string" and v ~= "", "must be a non-empty string" end,
    http_req = function(v) return type(v) == "string" and v ~= "", "must be a non-empty string" end,
    port = function(v) return positive_integer(v) and v <= 65535, "must be a port number" end,
    interval = function(v) return positive_integer(v), "must be a positive integer (ms)" end,
    timeout = function(v) return positive_integer(v), "must be a positive integer (ms)" end,
    fall = function(v) return positive_integer(v), "must be a positive integer" end,
    rise = function(v) return positive_integer(v), "must be a positive integer" end,
    concurrency = function(v) return positive_integer(v), "must be a positive integer" end,
    ssl_verify = function(v) return type(v) == "boolean", "must be true or false" end,
    valid_statuses = function(v)
        if type(v) ~= "table" or #v == 0 then
            return false, "must be a non-empty array of HTTP status codes"
        end
        for _, status in ipairs(v) do
            if not positive_integer(status) or status < 100 or status > 599 then
                return false, "must be a non-empty array of HTTP status codes"
            end
        end
        return true
    end,
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

local function check_options(where, options, errors)
    if type(options) ~= "table" then
        errors[#errors + 1] = where .. " must be a JSON object"
        return
    end
    for key, value in pairs(options) do
        local check = OPTION_CHECKS[key]
        if not check then
            errors[#errors + 1] = where .. ": unknown option \"" .. tostring(key) .. "\""
        else
            local ok, reason = check(value)
            if not ok then
                errors[#errors + 1] = where .. "." .. key .. " " .. reason
            end
        end
    end
end

-- Upstream names declared in the *.conf files of a directory (the same
-- non-recursive set that `include routes/*.conf` loads).
local function declared_upstreams(conf_dir)
    local names = {}
    local listing = io.popen("ls -1 '" .. conf_dir .. "' 2>/dev/null")
    if not listing then
        return names
    end
    for entry in listing:lines() do
        if entry:match("%.conf$") then
            local body = read_file(conf_dir .. "/" .. entry) or ""
            body = body:gsub("#[^\n]*", "")
            for name in body:gmatch("upstream%s+([^%s{]+)%s*{") do
                names[name] = true
            end
        end
    end
    listing:close()
    return names
end

-- Parses and checks <conf_dir>/healthchecks.json. Returns the decoded config
-- (nil when the file does not exist) and a list of errors. Upstream names are
-- cross-checked against the *.conf files only when check_names is set: that
-- forks `ls`, which is fine in `resty` but not worth doing in every worker.
function _M.load(conf_dir, check_names)
    local body = read_file(conf_dir .. "/healthchecks.json")
    if not body then
        return nil, {}
    end

    local config, decode_err = cjson.decode(body)
    if type(config) ~= "table" then
        return nil, { "healthchecks.json is not valid JSON: " .. tostring(decode_err) }
    end

    local errors = {}
    for key in pairs(config) do
        if key ~= "defaults" and key ~= "upstreams" then
            errors[#errors + 1] = "unknown top-level key \"" .. tostring(key) .. "\""
        end
    end
    if config.defaults ~= nil then
        check_options("defaults", config.defaults, errors)
    end
    if type(config.upstreams) ~= "table" then
        errors[#errors + 1] = "\"upstreams\" must be a JSON object"
        return config, errors
    end

    local declared = check_names and declared_upstreams(conf_dir)
    for name, spec in pairs(config.upstreams) do
        check_options("upstreams." .. name, spec, errors)
        if declared and not declared[name] then
            errors[#errors + 1] = "upstreams." .. name .. ": no `upstream " .. name .. " { ... }` in any *.conf"
        end
    end
    return config, errors
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
    local opts = merge(_M.BUILTIN_DEFAULTS, defaults, spec)
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

-- Called from init_worker with the published snapshot, which already passed
-- validate(); the type guards only protect against a worker crash.
function _M.spawn(path)
    local first_worker = ngx.worker.id() == 0
    local conf_dir = path:match("^(.*)/[^/]+$")

    local config, errors = _M.load(conf_dir)
    if not config then
        if #errors > 0 then
            ngx.log(ngx.ERR, "healthchecks: ", errors[1])
        elseif first_worker then
            ngx.log(ngx.WARN, "healthchecks: ", path, " not found, active health checks disabled")
        end
        return
    end
    if type(config.upstreams) ~= "table" then
        return
    end

    local defaults = type(config.defaults) == "table" and config.defaults or {}
    for upstream, spec in pairs(config.upstreams) do
        if type(spec) == "table" then
            local ok, spawn_err = hc.spawn_checker(checker_options(upstream, defaults, spec))
            if not ok then
                ngx.log(ngx.ERR, "healthchecks: upstream \"", upstream, "\": ", spawn_err)
            elseif first_worker then
                ngx.log(ngx.WARN, "healthchecks: active checks enabled for upstream \"", upstream, "\"")
            end
        end
    end
end

return _M

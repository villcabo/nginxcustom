-- Gateway-specific checks run by the entrypoint (through `resty`) on a
-- candidate conf.d, after `openresty -t` has accepted its syntax. They catch
-- configurations that nginx accepts today but that break the gateway later.

local healthchecks = require("gateway.healthchecks")

local _M = {}

local function read_file(path)
    local file = io.open(path, "r")
    if not file then
        return nil
    end
    local body = file:read("*a")
    file:close()
    return body
end

local function conf_files(conf_dir)
    local files = {}
    local listing = io.popen("ls -1 '" .. conf_dir .. "' 2>/dev/null")
    if listing then
        for entry in listing:lines() do
            if entry:match("%.conf$") then
                files[#files + 1] = entry
            end
        end
        listing:close()
    end
    return files
end

-- Hosts that never go through DNS at load time.
local function needs_dns(host)
    if host == "localhost" or host:match("^unix:") or host:match("^%[") then
        return false
    end
    return not host:match("^%d+%.%d+%.%d+%.%d+$")
end

-- A `server <hostname>` without `resolve` is resolved once while loading the
-- config: if that name is missing on the next start or reload the whole
-- gateway refuses to load, and a recreated backend keeps its stale IP.
local function check_upstream_servers(conf_dir, errors)
    for _, file in ipairs(conf_files(conf_dir)) do
        local body = (read_file(conf_dir .. "/" .. file) or ""):gsub("#[^\n]*", "")
        for name, block in body:gmatch("upstream%s+([^%s{]+)%s*(%b{})") do
            for directive in block:gmatch("[^;{}]+;") do
                local server_args = directive:match("^%s*server%s+(.-);$")
                if server_args then
                    local address = server_args:match("^(%S+)")
                    local host = address:match("^%[") and address or address:gsub(":%d+$", "")
                    if needs_dns(host) and not server_args:match("%f[%w]resolve%f[%W]") then
                        errors[#errors + 1] = string.format(
                            "%s: upstream %s: `server %s` needs `resolve` (and a `zone` in the upstream)",
                            file, name, address)
                    end
                end
            end
        end
    end
end

-- Entry point for `resty`: prints every problem and returns true when the
-- candidate directory is safe to publish.
function _M.run(conf_dir)
    local errors = {}
    check_upstream_servers(conf_dir, errors)
    local _, healthcheck_errors = healthchecks.load(conf_dir, true)
    for _, message in ipairs(healthcheck_errors) do
        errors[#errors + 1] = "healthchecks.json: " .. message
    end

    for _, message in ipairs(errors) do
        io.stderr:write("validation: ", message, "\n")
    end
    return #errors == 0
end

return _M

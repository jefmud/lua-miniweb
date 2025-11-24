-- miniweb.lua
--
-- Tiny Bottle-like web microframework in plain Lua.
-- Requires LuaSocket (luarocks install luasocket)

-- set the package paths varies with os and configurations
package.cpath = '/usr/local/lib/lua/5.4/?.so;/usr/lib/x86_64-linux-gnu/lua/5.4/?.so;/usr/lib/lua/5.4/?.so;/usr/local/lib/lua/5.4/loadall.so;./?.so'
package.path = './?.lua;/usr/share/lua/5.4/?.lua;/usr/share/lua/5.4/?/init.lua'

-- if this doesn't work, you may have to read documents
local socket = require "socket"

--########### Utility functions ###########--

local function url_decode(str)
    str = str:gsub("+", " ")
    str = str:gsub("%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end)
    return str
end

local function split_path(path)
    local parts = {}
    for part in string.gmatch(path, "[^/]+") do
        table.insert(parts, part)
    end
    return parts
end

-- pattern like "/hello/:name" or "/files/*rest" vs path like "/hello/jeff" or "/files/a/b.txt"
local function match_route(pattern, path)
    local params = {}

    local p_parts   = split_path(pattern)
    local path_parts = split_path(path)

    -- Look for a wildcard segment (e.g. "*rest") – we only support it as the LAST segment
    local wildcard_index = nil
    local wildcard_name  = nil

    for i, p in ipairs(p_parts) do
        if p:sub(1, 1) == "*" then
            wildcard_index = i
            wildcard_name  = p:sub(2)  -- may be "" if user wrote just "*"
            break
        end
    end

    if not wildcard_index then
        -- No wildcard → require exact number of segments
        if #p_parts ~= #path_parts then
            return nil
        end

        for i, p in ipairs(p_parts) do
            local seg = path_parts[i]
            if p:sub(1, 1) == ":" then
                local name = p:sub(2)
                params[name] = seg
            elseif p ~= seg then
                return nil
            end
        end

        return params
    end

    -- Wildcard present. We only support it as the last segment.
    if wildcard_index ~= #p_parts then
        -- For simplicity, reject patterns where wildcard is not last
        return nil
    end

    -- Pattern before wildcard must match as usual
    local fixed_count = wildcard_index - 1

    -- Path must have at least as many segments as the fixed part
    if #path_parts < fixed_count then
        return nil
    end

    -- Match fixed segments & normal :params
    for i = 1, fixed_count do
        local p   = p_parts[i]
        local seg = path_parts[i]

        if p:sub(1, 1) == ":" then
            local name = p:sub(2)
            params[name] = seg
        elseif p ~= seg then
            return nil
        end
    end

    -- Capture the rest into the wildcard param (could be empty)
    if wildcard_name and wildcard_name ~= "" then
        if #path_parts >= wildcard_index then
            params[wildcard_name] = table.concat(path_parts, "/", wildcard_index)
        else
            params[wildcard_name] = ""
        end
    end

    return params
end


local function parse_query(path)
    local path_only, query_str = path:match("([^?]+)%?(.*)")
    if not path_only then
        return path, {}
    end

    local query = {}
    for key, val in string.gmatch(query_str, "([^&=?]+)=?([^&]*)") do
        query[url_decode(key)] = url_decode(val)
    end

    return path_only, query
end

local function parse_form_body(body)
    local form = {}
    for key, val in string.gmatch(body, "([^&=?]+)=?([^&]*)") do
        form[url_decode(key)] = url_decode(val)
    end
    return form
end

local function reason_phrase(code)
    if code == 200 then return "OK"
    elseif code == 201 then return "Created"
    elseif code == 204 then return "No Content"
    elseif code == 401 then return "Unauthorized"
    elseif code == 403 then return "Forbidden"
    elseif code == 404 then return "Not Found"
    elseif code == 500 then return "Internal Server Error"
    else return "OK"
    end
end

-- very tiny JSON encoder (good enough for simple tables)
local function json_escape(str)
    str = str:gsub("\\", "\\\\")
    str = str:gsub("\"", "\\\"")
    str = str:gsub("\n", "\\n")
    str = str:gsub("\r", "\\r")
    return str
end

local function is_array(tbl)
    local n = 0
    for k, _ in pairs(tbl) do
        if type(k) ~= "number" then
            return false
        end
        if k > n then n = k end
    end
    return n == #tbl
end

local function encode_json(v)
    local t = type(v)
    if t == "nil" then
        return "null"
    elseif t == "number" or t == "boolean" then
        return tostring(v)
    elseif t == "string" then
        return '"' .. json_escape(v) .. '"'
    elseif t == "table" then
        if is_array(v) then
            local parts = {}
            for i = 1, #v do
                parts[i] = encode_json(v[i])
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            local parts = {}
            for k, val in pairs(v) do
                parts[#parts+1] =
                    '"' .. json_escape(tostring(k)) .. '":' .. encode_json(val)
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    else
        return "null"
    end
end

--########### Template loading + cache ###########--

-- Load raw template text, with optional cache table
local function load_template(path, cache)
    if cache and cache[path] then
        return cache[path]
    end
    local f, err = io.open(path, "rb")
    if not f then
        return nil, "Cannot open template: " .. tostring(err)
    end
    local txt = f:read("*all")
    f:close()
    if cache then
        cache[path] = txt
    end
    return txt
end

-- Tiny template renderer: {{ name }} substitution, no logic.
local function render_template(path, data, cache)
    local txt, err = load_template(path, cache)
    if not txt then
        return nil, err
    end

    data = data or {}

    txt = txt:gsub("{{%s*(.-)%s*}}", function(key)
        local v = data[key]
        if v == nil then return "" end
        return tostring(v)
    end)

    return txt
end

--########### MiniWeb class ###########--

local MiniWeb = {}
MiniWeb.__index = MiniWeb

function MiniWeb.new()
    local self = setmetatable({}, MiniWeb)
    self.routes          = {}
    self.before_handlers = {}  -- global middleware before routing
    self.after_handlers  = {}  -- global middleware after handler
    self.static_routes   = {}  -- { prefix = "/static", root = "./public" }
    self.template_cache  = {}  -- tiny template cache
    self.error_handlers  = {}  -- custom error handlers
    return self
end

-- add_route supports route-level middleware:
-- app:get("/path", mw1, mw2, handler)
function MiniWeb:add_route(method, pattern, ...)
    method = string.upper(method)
    local args = { ... }
    assert(#args >= 1, "Route requires at least a handler function")

    local handler = args[#args]
    local middlewares = {}

    for i = 1, #args - 1 do
        assert(type(args[i]) == "function", "Route middleware must be a function")
        table.insert(middlewares, args[i])
    end

    assert(type(handler) == "function", "Route handler must be a function")

    table.insert(self.routes, {
        method      = method,
        pattern     = pattern,
        handler     = handler,
        middlewares = middlewares,
    })
end

function MiniWeb:get(pattern, ...)
    self:add_route("GET", pattern, ...)
end

function MiniWeb:post(pattern, ...)
    self:add_route("POST", pattern, ...)
end

function MiniWeb:put(pattern, ...)
    self:add_route("PUT", pattern, ...)
end

function MiniWeb:delete(pattern, ...)
    self:add_route("DELETE", pattern, ...)
end

function MiniWeb:find_route(method, path)
    method = string.upper(method)
    for _, r in ipairs(self.routes) do
        if r.method == method then
            local params = match_route(r.pattern, path)
            if params then
                return r, params
            end
        end
    end
    return nil, nil
end

-- Global middleware registration
function MiniWeb:before(handler)
    table.insert(self.before_handlers, handler)
end

function MiniWeb:after(handler)
    table.insert(self.after_handlers, handler)
end

-- Register static file mapping: URL prefix -> filesystem root
-- Example: app:static("/static", "public")
function MiniWeb:static(url_prefix, root_dir)
    if not url_prefix:match("^/") then
        url_prefix = "/" .. url_prefix
    end
    if #url_prefix > 1 and url_prefix:sub(-1) == "/" then
        url_prefix = url_prefix:sub(1, -2)
    end

    table.insert(self.static_routes, {
        prefix = url_prefix,
        root   = root_dir,
    })
end

-- Template rendering helper (cached)
function MiniWeb:render(path, data)
    return render_template(path, data, self.template_cache)
end

-- Error handler registration
-- app:error(404, function(req, res, msg) ... end)
-- app:error("default", function(req, res, msg) ... end)
function MiniWeb:error(code_or_name, handler)
    self.error_handlers[code_or_name] = handler
end

--########### Response object ###########--

local function new_response()
    local res = {
        status  = 200,
        headers = {},
        body    = "",
    }

    function res:set_status(code)
        self.status = code
    end

    function res:set_header(name, value)
        self.headers[name] = value
    end

    function res:text(body, status)
        self.body = body or ""
        if status then self.status = status end
        self.headers["Content-Type"] =
            self.headers["Content-Type"] or "text/plain; charset=utf-8"
    end

    function res:html(body, status)
        self.body = body or ""
        if status then self.status = status end
        self.headers["Content-Type"] =
            self.headers["Content-Type"] or "text/html; charset=utf-8"
    end

    function res:json(data, status)
        local body = encode_json(data or {})
        self.body = body
        if status then self.status = status end
        self.headers["Content-Type"] =
            self.headers["Content-Type"] or "application/json; charset=utf-8"
    end

    return res
end

--########### Static file serving ###########--

local function guess_content_type(path)
    if path:match("%.html?$") then
        return "text/html; charset=utf-8"
    elseif path:match("%.css$") then
        return "text/css; charset=utf-8"
    elseif path:match("%.js$") then
        return "application/javascript; charset=utf-8"
    elseif path:match("%.png$") then
        return "image/png"
    elseif path:match("%.jpe?g$") then
        return "image/jpeg"
    elseif path:match("%.gif$") then
        return "image/gif"
    elseif path:match("%.svg$") then
        return "image/svg+xml"
    elseif path:match("%.ico$") then
        return "image/x-icon"
    else
        return "application/octet-stream"
    end
end

local function try_static(self, req, res)
    if req.method ~= "GET" then
        return false
    end

    for _, s in ipairs(self.static_routes) do
        local prefix = s.prefix
        if req.path:sub(1, #prefix) == prefix then
            local rel = req.path:sub(#prefix + 1)
            if rel == "" or rel == "/" then
                rel = "index.html"
            end
            rel = rel:gsub("^/", "")
            rel = rel:gsub("%.%.", "")

            local fullpath = s.root .. "/" .. rel
            local f = io.open(fullpath, "rb")
            if not f then
                return false
            end

            local content = f:read("*all")
            f:close()

            res.status = 200
            res.body   = content
            res.headers["Content-Type"] = guess_content_type(fullpath)
            return true
        end
    end

    return false
end

--########### Error handling ###########--

local function handle_error(self, status, req, res, default_msg)
    res.status = status
    local handler = self.error_handlers[status] or self.error_handlers["default"]

    if handler then
        local ok, b, s, h = pcall(handler, req, res, default_msg)
        if not ok then
            -- error inside error handler → generic 500
            res.status = 500
            res.body   = "Internal Server Error"
            res.headers = {}
            return
        end
        if b ~= nil then
            res.body = b or ""
            if s then res.status = s end
            if h then
                for k, v in pairs(h) do
                    res.headers[k] = v
                end
            end
        elseif (not res.body) or res.body == "" then
            res.body = default_msg or reason_phrase(status)
        end
    else
        res.body = default_msg or (tostring(status) .. " " .. reason_phrase(status))
    end
end

--########### Request handling ###########--

local function log_request(req, res)
    local remote_ip = req.remote_ip or "-"
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local method = req.method or "-"
    local path = req.raw_path or req.path or "-"
    local status = res.status or 0
    local user_agent = req.headers and (req.headers["user-agent"] or req.headers["User-Agent"]) or "-"
    print(string.format("%s - %s %s %s %d %s", remote_ip, timestamp, method, path, status, user_agent))
end

local function handle_client(self, client)
    local remote_ip, remote_port = client:getpeername()
    client:settimeout(1)

    -- Request line
    local line, err = client:receive("*l")
    if not line then
        client:close()
        return
    end

    local method, raw_path, httpver =
        string.match(line, "^(%w+)%s+(.-)%s+HTTP/(%d%.%d)")

    if not method then
        client:close()
        return
    end

    -- Headers
    local headers = {}
    while true do
        local h = client:receive("*l")
        if not h or h == "" then break end
        local name, value = h:match("^(.-):%s*(.*)")
        if name and value then
            headers[string.lower(name)] = value
        end
    end

    -- Body
    local body = ""
    local content_length = tonumber(headers["content-length"] or "0") or 0
    if content_length > 0 then
        body, err = client:receive(content_length)
        if not body then body = "" end
    end

    -- Query string
    local path, query = parse_query(raw_path)

    -- Simple form parsing
    local form = {}
    local ctype = (headers["content-type"] or ""):lower()
    if content_length > 0
       and ctype:match("application/x%-www%-form%-urlencoded") then
        form = parse_form_body(body)
    end

    local req = {
        method       = method,
        path         = path,
        raw_path     = raw_path,
        http_version = httpver,
        headers      = headers,
        params       = {},
        query        = query,
        body         = body,
        form         = form,
        remote_ip    = remote_ip,
        remote_port  = remote_port,
        context      = {},   -- for middleware/handlers to stash stuff
    }

    local res = new_response()

    -- GLOBAL BEFORE middleware
    for _, mw in ipairs(self.before_handlers) do
        local ok, mw_err = pcall(mw, req)
        if not ok then
            print("Error in before middleware: " .. tostring(mw_err))
        end
    end

    -- FIRST: static file handling
    local is_static = try_static(self, req, res)

    if not is_static then
        -- Route dispatch
        local route, params = self:find_route(method, path)

        if route then
            req.params = params

            -- ROUTE-LEVEL MIDDLEWARE
            if route.middlewares and #route.middlewares > 0 then
                for _, mw in ipairs(route.middlewares) do
                    local ok, mw_err = pcall(mw, req, res)
                    if not ok then
                        print("Error in route middleware: " .. tostring(mw_err))
                    end
                    if req.context.halt then
                        break
                    end
                end
            end

            -- Call handler only if not halted
            if not req.context.halt then
                local ok, b, s, h = pcall(route.handler, req, res)

                if not ok then
                    handle_error(self, 500, req, res,
                        "Internal Server Error:\n" .. tostring(b))
                else
                    if b ~= nil then
                        res.body = b or ""
                        if s then res.status = s end
                        if h then
                            for k, v in pairs(h) do
                                res.headers[k] = v
                            end
                        end
                    end
                end
            end
        else
            handle_error(self, 404, req, res, "Not found")
        end
    end

    -- GLOBAL AFTER middleware
    for _, mw in ipairs(self.after_handlers) do
        local ok, mw_err = pcall(mw, req, res)
        if not ok then
            print("Error in after middleware: " .. tostring(mw_err))
        end
    end

    -- Defaults
    if not res.headers["Content-Type"] then
        res.headers["Content-Type"] = "text/plain"
    end
    res.headers["Content-Length"] = #res.body

    -- Send response
    client:send(string.format("HTTP/1.1 %d %s\r\n",
                              res.status, reason_phrase(res.status)))
    for k, v in pairs(res.headers) do
        client:send(string.format("%s: %s\r\n", k, v))
    end
    client:send("\r\n")
    client:send(res.body)
    log_request(req, res)
    client:close()
end

function MiniWeb:run(host, port)
    host = host or "127.0.0.1"
    port = port or 8080

    local server, err = socket.bind(host, port)
    assert(server, "Could not bind: " .. tostring(err))
    print("MiniWeb listening on http://" .. host .. ":" .. port)

    while true do
        local client = server:accept()
        if client then
            handle_client(self, client)
        end
    end
end

--########### Module API ###########--

local M = {}

function M.new()
    return MiniWeb.new()
end

-- Optional: expose renderer (uses no cache if called directly)
function M.render_string(template_path, data)
    return render_template(template_path, data, nil)
end

return M

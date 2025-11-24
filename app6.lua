local miniweb = require "miniweb"
local app = miniweb.new()

-- Global logging
app:before(function(req)
    --print(string.format("[REQ] %s %s", req.method, req.path))
end)

app:after(function(req, res)
    res:set_header("X-Powered-By", "MiniWeb/Lua")
end)

-- Static files
app:static("/static", "public")

-- Custom 404 handler
app:error(404, function(req, res, msg)
    local html, err = app:render("templates/404.html", {
        path    = req.path,
        message = msg or "Not found",
    })
    if not html then
        res:text("404 Not found: " .. tostring(req.path), 404)
        return
    end
    res:html(html, 404)
end)

-- Custom 500 handler
app:error(500, function(req, res, msg)
    local html, err = app:render("templates/500.html", {
        message = msg or "Internal server error",
    })
    if not html then
        res:text("Internal server error", 500)
        return
    end
    res:html(html, 500)
end)

-- Optional default handler for any other status codes:
-- app:error("default", function(req, res, msg)
--     res:text("Error: " .. tostring(msg), res.status or 500)
-- end)

-- Home page (cached template)
app:get("/", function(req, res)
    local html, err = app:render("templates/index.html", {
        title   = "MiniWeb Demo",
        heading = "Welcome to MiniWeb",
        name    = "Jeff",
    })
    if not html then
        -- trigger error handler 500
        error("Failed to render index: " .. tostring(err))
    end
    res:html(html)
end)

-- Route that intentionally throws to demo 500 handler
app:get("/boom", function(req, res)
    error("Kaboom from /boom route!")
end)

app:run("127.0.0.1", 8080)

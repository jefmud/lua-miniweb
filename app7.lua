local miniweb = require "miniweb"
local app = miniweb.new()


app:get("/", function(req, res)
    res:html(app:render("templates/DemoMiniweb.html"))
end)

app:get("/documentation", function(req, res)
    res:html(app:render("templates/documentation.html"))
end)

-- Serve any path under /files/ using a wildcard
-- e.g. GET /files/a/b/c.txt → req.params.path == "a/b/c.txt"
app:get("/files/*path", function(req, res)
    local path = req.params.path or ""
    res:text("You asked for file path: " .. path .. "\n")
end)

-- Another example: catch-all page route
-- e.g. /pages/about/team → slug == "about/team"
app:get("/pages/*slug", function(req, res)
    res:json({
        route = "pages",
        slug  = req.params.slug,
    })
end)

app:run("0.0.0.0", 8080)

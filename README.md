# MiniWeb (Lua) – Documentation & Tutorial

A tiny Bottle-style web microframework written in plain Lua.

Disclaimer -- this is EARLY in development! Caveat Emptor.  Drop me a line if you are interested in this project.

---

## Index

1. [Introduction](#1-introduction)  
2. [Quickstart Tutorial](#2-quickstart-tutorial)  
3. [Installation & Setup](#3-installation--setup)  
4. [Request & Response Basics](#4-request--response-basics)  
5. [Routing](#5-routing)  
   - [5.1 Basic Routes](#51-basic-routes)  
   - [5.2 Path Parameters](#52-path-parameters)  
   - [5.3 Wildcard Routes](#53-wildcard-routes)  
   - [5.4 HTTP Verbs (GET/POST/PUT/DELETE)](#54-http-verbs-getpostputdelete)  
6. [Query Strings & Form Data](#6-query-strings--form-data)  
7. [Middleware](#7-middleware)  
   - [7.1 Global `before` & `after`](#71-global-before--after)  
   - [7.2 Route-level Middleware](#72-route-level-middleware)  
8. [Response Object Helpers](#8-response-object-helpers)  
9. [Templates & Template Cache](#9-templates--template-cache)  
10. [Static File Serving](#10-static-file-serving)  
11. [Error Handling](#11-error-handling)  
12. [API Reference Summary](#12-api-reference-summary)  

---

## 1. Introduction

**MiniWeb** is a simple, educational web framework for Lua inspired by microframeworks like Bottle. It is designed to be:

- Single-file library (`miniweb.lua`)
- Minimal dependencies (only `LuaSocket`)
- Easy to read, tweak, and extend

It provides:

- Routing with path parameters and wildcards
- Support for GET/POST/PUT/DELETE
- Query string & form data parsing
- Global and route-level middleware
- A simple response object with helpers (`res:text`, `res:html`, `res:json`)
- Template rendering with a tiny cache
- Static file serving
- Customizable error handlers

---

## 2. Quickstart Tutorial

### 2.1 Directory layout

Example layout:

```text
.
├── miniweb.lua          <-- the framework
├── app.lua              <-- your application
├── templates
│   └── index.html
└── public
    └── style.css
```

### 2.2 Minimal `app.lua`

```lua
local miniweb = require "miniweb"
local app = miniweb.new()

-- Global logging
app:before(function(req)
    print(string.format("[REQ] %s %s", req.method, req.path))
end)

-- Static files under /static
app:static("/static", "public")

-- Home page using a template
app:get("/", function(req, res)
    local html, err = app:render("templates/index.html", {
        title   = "MiniWeb Demo",
        heading = "Welcome to MiniWeb",
        name    = "Jeff",
    })
    if not html then
        res:text("Template error: " .. tostring(err), 500)
        return
    end
    res:html(html)
end)

-- Simple JSON endpoint
app:get("/api/ping", function(req, res)
    res:json({ status = "ok", time = os.time() })
end)

app:run("127.0.0.1", 8080)
```

### 2.3 Run the server

```bash
lua app.lua
# Visit: http://127.0.0.1:8080/
```

---

## 3. Installation & Setup

### 3.1 Requirements

- Lua 5.1–5.4 (or LuaJIT)
- `LuaSocket` (installed via LuaRocks)

### 3.2 Install LuaSocket

```bash
luarocks install luasocket
```

### 3.3 Add `miniweb.lua` to your project

Place `miniweb.lua` in your working directory (or somewhere in `package.path`) so you can:

```lua
local miniweb = require "miniweb"
local app = miniweb.new()
```

---

## 4. Request & Response Basics

### 4.1 Request object

Each route handler receives a `req` table with:

- `req.method` — HTTP method (e.g. `"GET"`)
- `req.path` — path without query, e.g. `"/hello/Jeff"`
- `req.raw_path` — original path including query string
- `req.http_version` — e.g. `"1.1"`
- `req.headers` — table of lowercase header names → values
- `req.params` — path parameters (e.g. `:name`, `*rest`)
- `req.query` — query string table
- `req.body` — raw request body (string)
- `req.form` — parsed form data (for `application/x-www-form-urlencoded`)
- `req.context` — free scratchpad shared across middleware/handlers

### 4.2 Response object

Each handler also receives a `res` object which you normally use via helper methods.

Example:

```lua
app:get("/plain", function(req, res)
    res:text("Hello from MiniWeb!
")
end)
```

You can also use the “legacy” style where the handler `return`s:

```lua
app:get("/legacy", function(req, res)
    return "Legacy body
", 200, { ["X-Foo"] = "bar" }
end)
```

---

## 5. Routing

### 5.1 Basic Routes

Use `app:get`, `app:post`, `app:put`, `app:delete` to register routes. Each takes a path pattern and one or more functions (route-level middleware + handler).

```lua
-- Simple GET route
app:get("/", function(req, res)
    res:text("Hello from /.
")
end)

-- Another GET route
app:get("/about", function(req, res)
    res:html("<h1>About</h1><p>MiniWeb demo.</p>")
end)
```

---

### 5.2 Path Parameters

You can define named parameters with `:name`. Each parameter is exposed as `req.params.<name>`.

```lua
-- /hello/Jeff → req.params.name == "Jeff"
app:get("/hello/:name", function(req, res)
    local name = req.params.name or "world"
    res:text("Hello, " .. name .. "!
")
end)

-- /users/42/posts/3
app:get("/users/:uid/posts/:pid", function(req, res)
    local uid = req.params.uid
    local pid = req.params.pid
    res:json({ user = uid, post = pid })
end)
```

---

### 5.3 Wildcard Routes

Wildcards use `*name` and are supported as the **final** path segment. Everything after that point is captured into `req.params[name]`.

```lua
-- /files/a.txt          → path = "a.txt"
-- /files/sub/dir/x.bin  → path = "sub/dir/x.bin"
app:get("/files/*path", function(req, res)
    local path = req.params.path or ""
    res:text("You requested file path: " .. path .. "
")
end)

-- /pages/about/team → slug = "about/team"
app:get("/pages/*slug", function(req, res)
    res:json({
        route = "pages",
        slug  = req.params.slug
    })
end)
```

---

### 5.4 HTTP Verbs (GET/POST/PUT/DELETE)

```lua
local items = {}

-- Create via POST
app:post("/items", function(req, res)
    local name  = req.form.name  or "unnamed"
    local value = req.form.value or "0"
    local id = #items + 1
    items[id] = { id = id, name = name, value = value }
    res:json(items[id], 201)
end)

-- List via GET
app:get("/items", function(req, res)
    res:json(items)
end)

-- Update via PUT
app:put("/items/:id", function(req, res)
    local id = tonumber(req.params.id or "0") or 0
    if not items[id] then
        res:text("Not found
", 404)
        return
    end
    items[id].name  = req.form.name  or items[id].name
    items[id].value = req.form.value or items[id].value
    res:json(items[id])
end)

-- Delete via DELETE
app:delete("/items/:id", function(req, res)
    local id = tonumber(req.params.id or "0") or 0
    if not items[id] then
        res:text("Not found
", 404)
        return
    end
    table.remove(items, id)
    res:text("Deleted
")
end)
```

Tutorial testing with `curl`:

```bash
# Create items
curl -X POST -d "name=foo&value=1" http://127.0.0.1:8080/items
curl -X POST -d "name=bar&value=2" http://127.0.0.1:8080/items

# List
curl http://127.0.0.1:8080/items

# Update
curl -X PUT -d "name=baz" http://127.0.0.1:8080/items/1

# Delete
curl -X DELETE http://127.0.0.1:8080/items/2
```

---

## 6. Query Strings & Form Data

### 6.1 Query strings

Query strings are parsed into `req.query`. Keys and values are URL-decoded.

```lua
-- /search?q=lua&page=2
app:get("/search", function(req, res)
    local q    = req.query.q    or ""
    local page = tonumber(req.query.page or "1") or 1
    res:text(string.format("Search for '%s', page %d
", q, page))
end)
```

### 6.2 Form data (POST/PUT)

For requests with `Content-Type: application/x-www-form-urlencoded`, the body is parsed into `req.form`.

```lua
-- curl -X POST -d "username=jeff&password=secret" --      http://127.0.0.1:8080/login
app:post("/login", function(req, res)
    local user = req.form.username or ""
    local pass = req.form.password or ""
    if user == "jeff" and pass == "secret" then
        res:text("Welcome, " .. user .. "
")
    else
        res:text("Invalid login
", 401)
    end
end)
```

> **Note:** For other content types (e.g. JSON), you can parse `req.body` manually in your handler.

---

## 7. Middleware

MiniWeb supports two levels of middleware:

- Global (`before` / `after`)
- Route-level (per route)

### 7.1 Global `before` & `after`

Global middleware runs for every request.

- `before` handlers run before routing.
- `after` handlers run after the handler, just before the response is sent.

```lua
-- Log every request (before routing)
app:before(function(req)
    req.context.start_time = os.clock()
    print(string.format("[REQ] %s %s", req.method, req.path))
end)

-- Add a header and timing info (after handler)
app:after(function(req, res)
    local elapsed = 0
    if req.context.start_time then
        elapsed = os.clock() - req.context.start_time
    end
    res:set_header("X-Powered-By", "MiniWeb/Lua")
    res:set_header("X-Response-Time", string.format("%.4f", elapsed))
end)
```

---

### 7.2 Route-level Middleware

Route-level middleware is attached to a specific route. You pass them as extra arguments before the actual handler:

```lua
-- Route-level middleware: require API key
local function require_api_key(req, res)
    local key = req.headers["x-api-key"]
    if key ~= "secret123" then
        res:set_status(401)
        res:text("Unauthorized
")
        req.context.halt = true   -- short-circuit: do not run handler
    end
end

-- Route-level middleware: log that we hit the "secret" route
local function route_logger(req, res)
    print("[Route] /secret hit")
end

-- Protected route
app:get("/secret", route_logger, require_api_key, function(req, res)
    res:text("Welcome to the secret area.
")
end)
```

Any route middleware can set `req.context.halt = true` to prevent the main handler from running.

---

## 8. Response Object Helpers

The `res` object wraps the response status, headers, and body.

Available methods:

- `res:set_status(code)`
- `res:set_header(name, value)`
- `res:text(body, status?)`
- `res:html(body, status?)`
- `res:json(table, status?)`

### 8.1 Examples

```lua
-- Plain text
app:get("/plain", function(req, res)
    res:text("Plain text response
")
end)

-- HTML
app:get("/welcome", function(req, res)
    res:html("<h1>Welcome</h1><p>Hello from MiniWeb</p>")
end)

-- JSON
app:get("/info", function(req, res)
    res:json({
        framework = "MiniWeb",
        version   = "0.1",
        features  = { "routing", "middleware", "templates" }
    })
end)

-- Manually adjust status and headers
app:get("/teapot", function(req, res)
    res:set_status(418)
    res:set_header("X-Tea", "Earl Grey")
    res:text("I'm a teapot
")
end)
```

---

## 9. Templates & Template Cache

MiniWeb provides a tiny template engine with a simple cache. Templates are text files with `{{ name }}` placeholders.

When you call `app:render(path, data)`:

- The template file is read once and cached in `app.template_cache`.
- Subsequent calls reuse the cached string (no disk re-read).

### 9.1 Template file

`templates/index.html`:

```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>{{ title }}</title>
</head>
<body>
  <h1>{{ heading }}</h1>
  <p>Hello, {{ name }}!</p>
</body>
</html>
```

### 9.2 Rendering from a route

```lua
app:get("/", function(req, res)
    local html, err = app:render("templates/index.html", {
        title   = "MiniWeb Demo",
        heading = "Welcome",
        name    = "Jeff",
    })
    if not html then
        res:text("Template error: " .. tostring(err), 500)
        return
    end
    res:html(html)
end)
```

> **Note:** The template engine is intentionally minimal: it only supports `{{ key }}` substitutions and no control flow (loops, conditionals, etc.).

---

## 10. Static File Serving

Static files (CSS, JS, images) can be served via:

```lua
app:static(url_prefix, root_dir)
```

Only `GET` is supported.

### 10.1 Configuration

```lua
-- Serve /static/* from ./public
app:static("/static", "public")
```

For example:

- Request to `/static/style.css` → serves `public/style.css` (if it exists).

### 10.2 Example usage in a template

```html
<link rel="stylesheet" href="/static/style.css">
<img src="/static/logo.png" alt="Logo">
```

Content type is guessed from the file extension (e.g. `.css`, `.js`, `.png`, `.jpg`, etc.).

---

## 11. Error Handling

MiniWeb lets you register custom error handlers using:

```lua
app:error(code_or_name, handler)
```

Where:

- `app:error(404, handler)` — handle 404 Not Found
- `app:error(500, handler)` — handle 500 Server Error
- `app:error("default", handler)` — fallback for other statuses

### 11.1 Example: HTML 404 page

`templates/404.html`:

```html
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>Not Found</title></head>
<body>
  <h1>404 - Not Found</h1>
  <p>No route for <code>{{ path }}</code>.</p>
</body>
</html>
```

Register the handler:

```lua
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
```

---

### 11.2 Example: 500 error handler

`templates/500.html`:

```html
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>Server Error</title></head>
<body>
  <h1>500 - Internal Server Error</h1>
  <pre>{{ message }}</pre>
</body>
</html>
```

Register the handler and a route that intentionally fails:

```lua
app:error(500, function(req, res, msg)
    local html, err = app:render("templates/500.html", {
        message = msg or "Something went wrong",
    })
    if not html then
        res:text("Internal server error", 500)
        return
    end
    res:html(html, 500)
end)

-- Route that intentionally fails to demonstrate 500 page
app:get("/boom", function(req, res)
    error("Kaboom from /boom")
end)
```

---

### 11.3 Default error handler

You can register a catch-all error handler:

```lua
app:error("default", function(req, res, msg)
    -- Will be used for statuses without a specific handler
    res:text(
        "Error " .. tostring(res.status or "?") ..
        ": " .. tostring(msg or "Unknown") .. "
",
        res.status or 500
    )
end)
```

---

## 12. API Reference Summary

### 12.1 Module

```lua
local miniweb = require "miniweb"
local app = miniweb.new()
```

### 12.2 Application methods

- `app:get(pattern, [mw1, ...], handler)`
- `app:post(pattern, [mw1, ...], handler)`
- `app:put(pattern, [mw1, ...], handler)`
- `app:delete(pattern, [mw1, ...], handler)`
- `app:before(handler)` — global “before” middleware
- `app:after(handler)` — global “after” middleware
- `app:static(url_prefix, root_dir)` — static file mapping
- `app:render(path, data)` — render template (cached)
- `app:error(code_or_name, handler)` — error handlers
- `app:run(host, port)` — start the server

### 12.3 Route patterns

- Literal segments:  
  `"/about"`, `"/users/list"`
- Named params:  
  `"/hello/:name"`, `"/users/:id/posts/:pid"`
- Wildcard (last segment only):  
  `"/files/*path"`, `"/pages/*slug"`

### 12.4 Request fields

- `req.method`, `req.path`, `req.raw_path`, `req.http_version`
- `req.headers`, `req.params`, `req.query`
- `req.body`, `req.form`
- `req.context` — shared scratchpad across middleware/handlers

### 12.5 Response methods

- `res:set_status(code)`
- `res:set_header(name, value)`
- `res:text(body, status?)`
- `res:html(body, status?)`
- `res:json(table, status?)`

---

You can drop this Markdown into a `README.md` next to `miniweb.lua` so you can edit it in your favorite Markdown editor and keep the documentation close to the code.

-- Internal Initializr metadata helpers. Not a public test surface.

local version = require("nvim-spring.version")

local M = {}

M.ACCEPT = "application/vnd.initializr.v2.3+json"
M.USER_AGENT = "nvim-spring/" .. version

function M.headers()
  return {
    Accept = M.ACCEPT,
    ["User-Agent"] = M.USER_AGENT,
  }
end

local function is_option_list(values, require_id)
  if type(values) ~= "table" then
    return false
  end
  for _, value in ipairs(values) do
    if type(value) ~= "table" then
      return false
    end
    if require_id and type(value.id) ~= "string" then
      return false
    end
    if value.tags ~= nil and type(value.tags) ~= "table" then
      return false
    end
    if value.values ~= nil and not is_option_list(value.values, false) then
      return false
    end
  end
  return true
end

function M.is_metadata(body)
  if type(body) ~= "table" then
    return false
  end
  if type(body.bootVersion) ~= "table" or not is_option_list(body.bootVersion.values, true) then
    return false
  end
  if type(body.javaVersion) ~= "table" or not is_option_list(body.javaVersion.values, true) then
    return false
  end
  if type(body.dependencies) ~= "table" or not is_option_list(body.dependencies.values, false) then
    return false
  end
  if type(body.type) ~= "table" or not is_option_list(body.type.values, true) then
    return false
  end
  return true
end

function M.maven_project_type(meta)
  local by_id
  for _, value in ipairs(meta.type.values) do
    local tags = value.tags or {}
    if tags.build == "maven" and (tags.format == "project" or tags.format == nil) then
      return value.id
    end
    if value.id == "maven-project" then
      by_id = value.id
    end
  end
  return by_id
end

function M.is_snapshot(id)
  return tostring(id or ""):upper():find("SNAPSHOT", 1, true) ~= nil
end

function M.default_boot(meta)
  local default = meta.bootVersion and meta.bootVersion.default
  if default then
    return default
  end
  for _, value in ipairs((meta.bootVersion and meta.bootVersion.values) or {}) do
    if not M.is_snapshot(value.id) then
      return value.id
    end
  end
  local first = meta.bootVersion and meta.bootVersion.values and meta.bootVersion.values[1]
  return first and first.id
end

function M.parse_language_level(id)
  if not id then
    return nil
  end
  local raw = tostring(id)
  local legacy = raw:match("^1%.(%d+)")
  if legacy then
    return tonumber(legacy)
  end
  return tonumber(raw:match("^(%d+)"))
end

function M.default_java(meta, host_major)
  local catalog_default = meta.javaVersion and meta.javaVersion.default
  local parsed = {}
  for _, value in ipairs((meta.javaVersion and meta.javaVersion.values) or {}) do
    local n = M.parse_language_level(value.id)
    if n then
      parsed[#parsed + 1] = { id = value.id, n = n }
    end
  end
  table.sort(parsed, function(a, b)
    return a.n < b.n
  end)
  if not host_major or #parsed == 0 then
    return catalog_default
  end
  local max = parsed[#parsed]
  if host_major > max.n then
    return max.id
  end
  local best
  for _, item in ipairs(parsed) do
    if item.n <= host_major then
      best = item.id
    end
  end
  if not best then
    return catalog_default
  end
  return best
end

function M.dependency_values(meta)
  local out = {}
  local function walk(nodes)
    if not nodes then
      return
    end
    for _, node in ipairs(nodes) do
      if node.id then
        out[#out + 1] = node
      end
      if node.values then
        walk(node.values)
      end
    end
  end
  walk(meta.dependencies and meta.dependencies.values)
  return out
end

function M.wizard_spec(meta, defaults, source)
  return {
    title = "Initializr",
    finish = "generate",
    source = source,
    steps = {
      {
        id = "identity",
        title = "Identity",
        fields = {
          {
            name = "groupId",
            label = "Group",
            type = "text",
            default = (meta.groupId and meta.groupId.default) or "com.example",
          },
          {
            name = "artifactId",
            label = "Artifact",
            type = "text",
            default = (meta.artifactId and meta.artifactId.default) or "demo",
          },
          {
            name = "packageName",
            label = "Package",
            type = "text",
            default = (meta.packageName and meta.packageName.default) or "com.example.demo",
          },
        },
      },
      {
        id = "platform",
        title = "Platform",
        fields = {
          {
            name = "bootVersion",
            label = "Boot",
            type = "select",
            default = defaults.boot,
            values = meta.bootVersion.values,
          },
          {
            name = "javaVersion",
            label = "Java",
            type = "select",
            default = defaults.java,
            values = meta.javaVersion.values,
          },
        },
      },
      {
        id = "dependencies",
        title = "Dependencies",
        fields = {
          {
            name = "dependencies",
            label = "Dependencies",
            type = "multi",
            default = {},
            values = M.dependency_values(meta),
          },
        },
      },
    },
  }
end

function M.encode(s)
  return (tostring(s):gsub("([^%w%-_%.~])", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

function M.join_url(base, path)
  base = (base or ""):gsub("/+$", "")
  if path:sub(1, 1) ~= "/" then
    path = "/" .. path
  end
  return base .. path
end

function M.starter_url(base, params)
  local keys = {}
  for k in pairs(params) do
    keys[#keys + 1] = k
  end
  table.sort(keys)
  local parts = {}
  for _, k in ipairs(keys) do
    local v = params[k]
    if v ~= nil and v ~= "" then
      parts[#parts + 1] = M.encode(k) .. "=" .. M.encode(v)
    end
  end
  return M.join_url(base, "/starter.zip") .. "?" .. table.concat(parts, "&")
end

function M.dependency_query(value)
  if type(value) == "table" then
    local ids = {}
    for _, item in ipairs(value) do
      if type(item) == "table" then
        ids[#ids + 1] = item.id
      else
        ids[#ids + 1] = item
      end
    end
    return table.concat(ids, ",")
  end
  return value
end

function M.preview(answers)
  local artifact = answers.artifactId or "demo"
  local pkg = (answers.packageName or "com.example.demo"):gsub("%.", "/")
  local deps = M.dependency_query(answers.dependencies)
  if not deps or deps == "" then
    deps = "(none)"
  end
  local class = artifact:gsub("(%-[a-z])", function(s)
    return s:sub(2, 2):upper()
  end)
  class = class:sub(1, 1):upper() .. class:sub(2)
  class = class:gsub("[^%w]", "")
  return table.concat({
    artifact .. "/",
    "  pom.xml                  maven · boot " .. tostring(answers.bootVersion or "") .. " · java " .. tostring(answers.javaVersion or ""),
    "  src/main/java/" .. pkg .. "/",
    "    " .. class .. "Application.java",
    "  src/main/resources/",
    "    application.properties",
    "",
    "group:     " .. tostring(answers.groupId or ""),
    "deps:      " .. deps,
  }, "\n")
end

return M

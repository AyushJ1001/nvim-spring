-- Find / write a Maven Dependency. Internal to the action module.

local M = {}

local function trim(s)
  return (s:match("^%s*(.-)%s*$"))
end

local function is_java_identifier(part)
  return part:match("^[A-Za-z_][A-Za-z0-9_]*$") ~= nil
end

local function is_type_shaped(query)
  local parts = {}
  for part in (query .. "."):gmatch("([^%.]+)%.") do
    parts[#parts + 1] = part
  end
  if #parts == 0 then
    return false
  end
  for _, part in ipairs(parts) do
    if not is_java_identifier(part) then
      return false
    end
  end
  return parts[#parts]:match("^[A-Z]") ~= nil
end

local function classify_query(query)
  query = trim(query or "")
  local g, a, v = query:match("^([%w%.%-_]+):([%w%.%-_]+):([%w%.%-_]+)$")
  if g then
    return "coordinate", { g = g, a = a, v = v }
  end
  g, a = query:match("^([%w%.%-_]+):([%w%.%-_]+)$")
  if g then
    return "coordinate", { g = g, a = a }
  end
  if is_type_shaped(query) then
    if query:find(".", 1, true) then
      return "fqcn", query
    end
    return "simple", query
  end
  return "keyword", query
end

local function hit_version(hit)
  return hit.v or hit.latestVersion
end

local function normalize_hits(docs)
  local hits = {}
  for _, doc in ipairs(docs or {}) do
    if doc.g and doc.a then
      hits[#hits + 1] = {
        g = doc.g,
        a = doc.a,
        v = hit_version(doc),
        label = doc.g .. ":" .. doc.a .. (hit_version(doc) and (":" .. hit_version(doc)) or ""),
      }
    end
  end
  return hits
end

function M.unique_gav(hits)
  if not hits or #hits == 0 then
    return nil
  end
  local first = hits[1]
  for i = 2, #hits do
    if hits[i].g ~= first.g or hits[i].a ~= first.a then
      return nil
    end
  end
  return first
end

function M.search(central, query)
  local kind, parsed = classify_query(query)
  local docs, err
  if kind == "coordinate" then
    docs, err = central:search_coordinates(parsed.g, parsed.a, parsed.v)
  elseif kind == "fqcn" then
    docs, err = central:search_class(parsed, true)
  elseif kind == "simple" then
    docs, err = central:search_class(parsed, false)
  else
    docs, err = central:search_keyword(parsed)
  end
  if err then
    return nil, err
  end
  return normalize_hits(docs), nil, kind
end

function M.should_auto_apply(kind, hits)
  if kind ~= "coordinate" and kind ~= "fqcn" then
    return false
  end
  return M.unique_gav(hits) ~= nil
end

local function tag(xml, name)
  if not xml then
    return nil
  end
  local escaped = name:gsub("(%W)", "%%%1")
  return xml:match("<" .. escaped .. "[^>]*>%s*(.-)%s*</" .. escaped .. ">")
end

local function spans(xml, open_tag, close_tag)
  local found = {}
  local pos = 1
  while true do
    local s = xml:find(open_tag, pos, true)
    if not s then
      break
    end
    local e = xml:find(close_tag, s + #open_tag, true)
    if not e then
      break
    end
    local close_end = e + #close_tag - 1
    found[#found + 1] = { s, close_end }
    pos = close_end + 1
  end
  return found
end

local function inside(pos, found)
  for _, span in ipairs(found) do
    if pos >= span[1] and pos <= span[2] then
      return true
    end
  end
  return false
end

function M.parseable(pom)
  return type(pom) == "string" and pom:find("<project", 1, true) and pom:find("</project>", 1, true)
end

local function project_dependencies_region(pom)
  local skip = spans(pom, "<dependencyManagement>", "</dependencyManagement>")
  for _, extra in ipairs({
    spans(pom, "<pluginManagement>", "</pluginManagement>"),
    spans(pom, "<plugin>", "</plugin>"),
  }) do
    for _, span in ipairs(extra) do
      skip[#skip + 1] = span
    end
  end
  local pos = 1
  while true do
    local s = pom:find("<dependencies>", pos, true)
    if not s then
      return nil
    end
    if not inside(s, skip) then
      local e = pom:find("</dependencies>", s + #"<dependencies>", true)
      if not e then
        return nil
      end
      return s, e + #"</dependencies>" - 1
    end
    pos = s + 1
  end
end

local function each_project_dependency(pom, fn)
  local s, e = project_dependencies_region(pom)
  if not s then
    return
  end
  local body = pom:sub(s, e)
  for dep in body:gmatch("<dependency[^>]*>(.-)</dependency>") do
    fn(tag(dep, "groupId"), tag(dep, "artifactId"), dep)
  end
end

function M.has_gav(pom, g, a)
  local found = false
  each_project_dependency(pom, function(dg, da)
    if dg == g and da == a then
      found = true
    end
  end)
  return found
end

local function collect_managed_from_xml(xml, managed)
  local dm = tag(xml, "dependencyManagement")
  if not dm then
    return
  end
  for dep in dm:gmatch("<dependency[^>]*>(.-)</dependency>") do
    local g, a = tag(dep, "groupId"), tag(dep, "artifactId")
    if g and a then
      managed[g .. ":" .. a] = {
        g = g,
        a = a,
        v = tag(dep, "version"),
        type = tag(dep, "type"),
        scope = tag(dep, "scope"),
      }
    end
  end
end

function M.is_managed(pom, g, a, central)
  local managed = {}
  local seen = {}
  local function absorb(xml)
    if not xml then
      return
    end
    local before = {}
    for key in pairs(managed) do
      before[key] = true
    end
    collect_managed_from_xml(xml, managed)
    if not (central and central.fetch_pom) then
      return
    end
    for key, info in pairs(managed) do
      if not before[key] and info.type == "pom" and info.scope == "import" and info.v then
        local id = info.g .. ":" .. info.a .. ":" .. info.v
        if not seen[id] then
          seen[id] = true
          absorb(central:fetch_pom(info.g, info.a, info.v))
        end
      end
    end
  end
  absorb(pom)
  local parent = tag(pom, "parent")
  if parent and central and central.fetch_pom then
    local pg, pa, pv = tag(parent, "groupId"), tag(parent, "artifactId"), tag(parent, "version")
    if pg and pa and pv then
      local id = pg .. ":" .. pa .. ":" .. pv
      if not seen[id] then
        seen[id] = true
        absorb(central:fetch_pom(pg, pa, pv))
      end
    end
  end
  return managed[g .. ":" .. a] ~= nil
end

local function dependency_xml(hit, opts)
  opts = opts or {}
  local lines = {
    "    <dependency>",
    "      <groupId>" .. hit.g .. "</groupId>",
    "      <artifactId>" .. hit.a .. "</artifactId>",
  }
  if hit.v and not opts.omit_version then
    lines[#lines + 1] = "      <version>" .. hit.v .. "</version>"
  end
  if opts.scope then
    lines[#lines + 1] = "      <scope>" .. opts.scope .. "</scope>"
  end
  lines[#lines + 1] = "    </dependency>"
  return table.concat(lines, "\n")
end

function M.insert(pom, hit, opts)
  opts = opts or {}
  local block = dependency_xml(hit, opts)
  local s = project_dependencies_region(pom)
  if s then
    local close = pom:find("</dependencies>", s, true)
    local prefix = pom:sub(1, close - 1):gsub("%s*$", "")
    return prefix .. "\n" .. block .. "\n  " .. pom:sub(close)
  end
  local close = pom:find("</project>", 1, true)
  if not close then
    return nil
  end
  local section = "  <dependencies>\n" .. block .. "\n  </dependencies>\n"
  return pom:sub(1, close - 1) .. section .. pom:sub(close)
end

function M.test_scope(path)
  if not path then
    return nil
  end
  if path:find("src/test/java", 1, true) then
    return "test"
  end
  return nil
end

return M

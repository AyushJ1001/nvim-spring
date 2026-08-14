-- Package view model. Internal to the action module.

local M = {}

local MAVEN_JAVA_ROOTS = {
  "src/main/java",
  "src/test/java",
}

local function tag(xml, name)
  local escaped = name:gsub("(%W)", "%%%1")
  return xml and xml:match("<" .. escaped .. "[^>]*>%s*(.-)%s*</" .. escaped .. ">")
end

local function pom_without_parent(fs)
  if not fs:exists("pom.xml") then
    return ""
  end
  return (fs:read("pom.xml") or ""):gsub("<parent>.-</parent>", "")
end

local function project_name(fs)
  local artifact = tag(pom_without_parent(fs), "artifactId")
  if artifact and artifact ~= "" then
    return artifact
  end
  local cwd = fs:cwd() or ""
  return cwd:match("([^/]+)$") or cwd
end

local function collect_packages(fs, root_path)
  local packages = {}
  local seen = {}

  local function walk(dir, rel)
    if not fs:is_dir(dir) then
      return
    end
    local names = fs:list(dir)
    local has_java = false
    for _, name in ipairs(names) do
      local child = dir .. "/" .. name
      if fs:is_dir(child) then
        local next_rel = rel == "" and name or (rel .. "/" .. name)
        walk(child, next_rel)
      elseif name:match("%.java$") then
        has_java = true
      end
    end
    if has_java then
      local pkg = rel:gsub("/", ".")
      if not seen[pkg] then
        seen[pkg] = true
        packages[#packages + 1] = pkg
      end
    end
  end

  walk(root_path, "")
  table.sort(packages)
  return packages
end

local function maven_java_roots(fs)
  local pom = pom_without_parent(fs)
  return {
    tag(pom, "sourceDirectory") or MAVEN_JAVA_ROOTS[1],
    tag(pom, "testSourceDirectory") or MAVEN_JAVA_ROOTS[2],
  }
end

local function root_entry(fs, path)
  return {
    path = path,
    packages = collect_packages(fs, path),
  }
end

local function maven_roots(fs)
  local roots = {}
  for _, path in ipairs(maven_java_roots(fs)) do
    if fs:is_dir(path) then
      roots[#roots + 1] = root_entry(fs, path)
    end
  end
  return roots
end

local function strip_file_uri(path)
  path = path:gsub("^file://localhost", "")
  path = path:gsub("^file://", "")
  path = path:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end)
  return path
end

local function relative_to_workspace(fs, path)
  if not path or path == "" then
    return nil
  end
  path = strip_file_uri(path)
  local cwd = fs:cwd()
  if cwd and path:sub(1, #cwd + 1) == cwd .. "/" then
    return path:sub(#cwd + 2)
  end
  if cwd and path == cwd then
    return ""
  end
  if path:sub(1, 1) == "/" or path:match("^%a:[/\\]") then
    return nil
  end
  if path:sub(1, 3) == "../" or path == ".." then
    return nil
  end
  return path
end

local function jdtls_roots(fs, jdtls)
  if not jdtls or not jdtls:is_running() then
    return nil
  end
  local listed = jdtls:list_source_paths()
  if type(listed) ~= "table" or #listed == 0 then
    return nil
  end
  local roots = {}
  local seen = {}
  for _, entry in ipairs(listed) do
    local path = relative_to_workspace(fs, entry.path)
      or relative_to_workspace(fs, entry.displayPath)
    if path and path ~= "" and not seen[path] then
      seen[path] = true
      roots[#roots + 1] = root_entry(fs, path)
    end
  end
  if #roots == 0 then
    return nil
  end
  return roots
end

function M.relative(fs, path)
  return relative_to_workspace(fs, path)
end

function M.build(fs, jdtls)
  return {
    name = project_name(fs),
    roots = jdtls_roots(fs, jdtls) or maven_roots(fs),
  }
end

return M

-- Scaffold kinds, preview, and write. Internal to the action module.

local package_view = require("nvim-spring.package_view")
local workspace = require("nvim-spring.workspace")

local M = {}

local JAVA_KINDS = {
  { id = "Class", keyword = "class" },
  { id = "Interface", keyword = "interface" },
  { id = "Record", keyword = "record" },
  { id = "Enum", keyword = "enum" },
}

local BOOT_KINDS = {
  {
    id = "RestController",
    keyword = "class",
    annotation = "RestController",
    import = "org.springframework.web.bind.annotation.RestController",
  },
  {
    id = "Controller",
    keyword = "class",
    annotation = "Controller",
    import = "org.springframework.stereotype.Controller",
  },
  {
    id = "Service",
    keyword = "class",
    annotation = "Service",
    import = "org.springframework.stereotype.Service",
  },
  {
    id = "Repository",
    keyword = "interface",
    annotation = "Repository",
    import = "org.springframework.stereotype.Repository",
  },
  {
    id = "Component",
    keyword = "class",
    annotation = "Component",
    import = "org.springframework.stereotype.Component",
  },
  {
    id = "Configuration",
    keyword = "class",
    annotation = "Configuration",
    import = "org.springframework.context.annotation.Configuration",
  },
}

function M.kinds(fs)
  local list = {}
  for _, kind in ipairs(JAVA_KINDS) do
    list[#list + 1] = kind
  end
  if workspace.is_boot(fs) then
    for _, kind in ipairs(BOOT_KINDS) do
      list[#list + 1] = kind
    end
  end
  return list
end

function M.kind_by_id(fs, id)
  for _, kind in ipairs(M.kinds(fs)) do
    if kind.id == id then
      return kind
    end
  end
end

function M.resolve_package(floor, query)
  floor = floor or ""
  query = query and query:match("^%s*(.-)%s*$") or ""
  if query == "" or query == floor then
    return floor
  end
  if floor == "" then
    return query
  end
  if query:sub(1, #floor + 1) == floor .. "." then
    return query
  end
  return floor .. "." .. query
end

function M.render(kind, pkg, name)
  local lines = {}
  if pkg and pkg ~= "" then
    lines[#lines + 1] = "package " .. pkg .. ";"
    lines[#lines + 1] = ""
  end
  if kind.import then
    lines[#lines + 1] = "import " .. kind.import .. ";"
    lines[#lines + 1] = ""
  end
  if kind.annotation then
    lines[#lines + 1] = "@" .. kind.annotation
  end
  if kind.keyword == "record" then
    lines[#lines + 1] = "public record " .. name .. "() {"
  else
    lines[#lines + 1] = "public " .. kind.keyword .. " " .. name .. " {"
  end
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

function M.path(root, pkg, name)
  local parts = { root }
  if pkg and pkg ~= "" then
    parts[#parts + 1] = (pkg:gsub("%.", "/"))
  end
  parts[#parts + 1] = name .. ".java"
  return table.concat(parts, "/")
end

function M.context(fs, jdtls, ui)
  local model = package_view.build(fs, jdtls)
  local roots = (model and model.roots) or {}
  local default_root = (roots[1] and roots[1].path) or "src/main/java"

  local sel = ui and ui.package_view_selection and ui:package_view_selection()
  if sel and sel.root then
    return { root = sel.root, package = sel.package or "" }
  end

  local file = ui and ui.current_file and ui:current_file()
  if file and file ~= "" then
    local rel = package_view.relative(fs, file)
    local root = default_root
    if rel then
      for _, entry in ipairs(roots) do
        if rel == entry.path or rel:sub(1, #entry.path + 1) == entry.path .. "/" then
          root = entry.path
          break
        end
      end
    end
    local content = fs:read(rel or file) or fs:read(file)
    local pkg = content and content:match("package%s+([%w%.]+)%s*;") or ""
    if pkg == "" and rel and rel:sub(1, #root + 1) == root .. "/" then
      local under = rel:sub(#root + 2)
      local dir = under:match("(.+)/[^/]+%.java$") or under:match("(.+)/[^/]+$")
      if dir then
        pkg = dir:gsub("/", ".")
      end
    end
    return { root = root, package = pkg }
  end

  return { root = default_root, package = "" }
end

local function descendant_packages(fs, jdtls, root, floor)
  local model = package_view.build(fs, jdtls)
  local pkgs = {}
  local seen = {}
  for _, entry in ipairs((model and model.roots) or {}) do
    if entry.path == root then
      for _, pkg in ipairs(entry.packages or {}) do
        if floor == "" or pkg == floor or pkg:sub(1, #floor + 1) == floor .. "." then
          if not seen[pkg] then
            seen[pkg] = true
            pkgs[#pkgs + 1] = pkg
          end
        end
      end
    end
  end
  if floor ~= "" and not seen[floor] then
    table.insert(pkgs, 1, floor)
  end
  return pkgs
end

function M.wizard_spec(fs, jdtls, ctx)
  local kind_values = {}
  for _, kind in ipairs(M.kinds(fs)) do
    kind_values[#kind_values + 1] = { id = kind.id, name = kind.id }
  end
  local pkg_values = {}
  for _, pkg in ipairs(descendant_packages(fs, jdtls, ctx.root, ctx.package)) do
    local desc = pkg == ctx.package and "selected Package" or "exists"
    local label = pkg
    if label == "" then
      label = "(default package)"
    end
    pkg_values[#pkg_values + 1] = { id = pkg, name = label, description = desc }
  end
  if #pkg_values == 0 then
    pkg_values[1] = {
      id = ctx.package,
      name = ctx.package == "" and "(default package)" or ctx.package,
      description = "selected Package",
    }
  end
  return {
    title = "Create Scaffold",
    steps = {
      {
        id = "kind",
        title = "Kind",
        fields = {
          {
            name = "kind",
            type = "select",
            values = kind_values,
            default = kind_values[1] and kind_values[1].id,
          },
        },
      },
      {
        id = "package",
        title = "Package",
        fields = {
          {
            name = "package",
            type = "select",
            values = pkg_values,
            default = ctx.package,
            allow_new = true,
            new_label = "new Package",
          },
        },
      },
      {
        id = "name",
        title = "Type name",
        fields = {
          { name = "name", type = "text", default = "" },
        },
      },
    },
  }
end

return M

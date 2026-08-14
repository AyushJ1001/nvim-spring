local workspace = require("nvim-spring.workspace")
local package_view = require("nvim-spring.package_view")
local dependency = require("nvim-spring.dependency")
local scaffold = require("nvim-spring.scaffold")

-- JDT diagnostic codes (org.eclipse.jdt.core.compiler.IProblem).
local UNDEFINED_TYPE = "16777218"
local UNDEFINED_NAME = "570425394"

local function diagnostic_code(diag)
  if not diag or diag.code == nil then
    return ""
  end
  return tostring(diag.code)
end

local function split_lines(source)
  local lines = {}
  local pos = 1
  while true do
    local nl = source:find("\n", pos, true)
    if not nl then
      lines[#lines + 1] = source:sub(pos)
      break
    end
    lines[#lines + 1] = source:sub(pos, nl - 1)
    pos = nl + 1
  end
  return lines
end

local function range_text(source, diag)
  if not source or not diag or not diag.lnum then
    return ""
  end
  local lines = split_lines(source)
  local line = lines[diag.lnum + 1]
  if not line then
    return ""
  end
  local col = diag.col or 0
  local end_col = diag.end_col or #line
  return line:sub(col + 1, end_col)
end

local function simple_name(type_text)
  return (type_text or ""):match("([%w_]+)$") or type_text
end

local function is_unresolved_type(diag, type_text)
  local code = diagnostic_code(diag)
  if code == UNDEFINED_TYPE then
    return type_text ~= ""
  end
  if code == UNDEFINED_NAME then
    return type_text:match("^[A-Z]") ~= nil
  end
  return false
end

local function overlaps_cursor(ctx, diag)
  local lnum = ctx.lnum
  if ctx.range and ctx.range.lnum ~= nil then
    lnum = ctx.range.lnum
  end
  if lnum == nil then
    return true
  end
  local col = ctx.col or (ctx.range and ctx.range.col) or 0
  local d1 = diag.lnum or 0
  local d2 = diag.end_lnum or d1
  if lnum < d1 or lnum > d2 then
    return false
  end
  if lnum == d1 and col < (diag.col or 0) then
    return false
  end
  if lnum == d2 and diag.end_col and col > diag.end_col then
    return false
  end
  return true
end

local Actions = {}
Actions.__index = Actions

local DEFAULT_KEYMAPS = {
  { "<leader>si", "SpringInit" },
  { "<leader>sc", "SpringCreate" },
  { "<leader>sp", "SpringPackages" },
  { "<leader>sa", "SpringAddDependency" },
  { "<leader>sr", "SpringRun" },
  { "<leader>ss", "SpringStop" },
}

function Actions.new(adapters)
  adapters = adapters or {}
  local self = setmetatable({}, Actions)
  self.fs = adapters.fs
  self.ui = adapters.ui
  self.jdtls = adapters.jdtls
  self.central = adapters.central
  self.host = adapters.host
  self.opts = adapters.opts or {}
  return self
end

function Actions:_merge_opts(opts)
  opts = opts or {}
  local merged = {}
  for k, v in pairs(self.opts) do
    merged[k] = v
  end
  for k, v in pairs(opts) do
    merged[k] = v
  end
  if merged.initializr_url == nil then
    merged.initializr_url = "https://start.spring.io"
  end
  if merged.keymaps == nil then
    merged.keymaps = true
  end
  self.opts = merged
end

function Actions:_ensure_jdtls()
  local jdtls = self.jdtls
  if not jdtls then
    return
  end
  if jdtls:is_present() and not jdtls:is_running() then
    jdtls:start()
  end
end

function Actions:_bind_keymaps()
  if self.opts.keymaps == false or not self.ui or not self.ui.keymap then
    return
  end
  for _, map in ipairs(DEFAULT_KEYMAPS) do
    self.ui:keymap("n", map[1], "<cmd>" .. map[2] .. "<cr>")
  end
end

function Actions:_register_code_actions()
  if not self.ui or not self.ui.register_code_actions then
    return
  end
  self.ui:register_code_actions(function(ctx)
    return self:code_actions(ctx)
  end, function(action)
    self:apply_code_action(action)
  end)
end

function Actions:_in_contract()
  local verdict = workspace.classify(self.fs)
  return not verdict.refuse
end

function Actions:_resource_rel(path)
  return path:match("src/main/resources/(.+)$")
end

function Actions:_copy_resource(path, rel)
  local content = self.fs:read(path)
  if not content then
    return
  end
  local dest = "target/classes/" .. rel
  local dir = dest:match("(.+)/[^/]+$")
  if dir and self.fs.mkdir then
    self.fs:mkdir(dir)
  end
  self.fs:write(dest, content)
end

function Actions:_compile_incremental()
  if self.jdtls and self.jdtls.compile then
    self.jdtls:compile("incremental")
  end
end

function Actions:_on_write(path)
  if not path or not self:_in_contract() or not workspace.is_spring_boot(self.fs) then
    return
  end
  if path:match("%.java$") then
    self:_compile_incremental()
    return
  end
  local rel = self:_resource_rel(path)
  if rel then
    self:_copy_resource(path, rel)
    self:_compile_incremental()
  end
end

function Actions:setup(opts)
  self:_merge_opts(opts)
  self:_bind_keymaps()
  self:_register_code_actions()
  if self.ui and self.ui.on_write then
    self.ui:on_write(function(path)
      self:_on_write(path)
    end)
  end
end

function Actions:ensure_jdtls()
  self:_ensure_jdtls()
end

-- Initializr does not need the workspace Build tool.
function Actions:init() end

function Actions:_gate()
  local verdict = workspace.classify(self.fs)
  if verdict.refuse then
    self.ui:notify(verdict.message)
    return false
  end
  return true
end

function Actions:_run_wizard(spec, on_done)
  if not self.ui or not self.ui.wizard then
    on_done(nil)
    return
  end
  local done = false
  local function finish(answers)
    if done then
      return
    end
    done = true
    on_done(answers)
  end
  local ret = self.ui:wizard(spec, finish)
  if ret ~= nil then
    if ret == false then
      finish(nil)
    else
      finish(ret)
    end
  end
end

function Actions:create()
  if not self:_gate() then
    return
  end
  local ctx = scaffold.context(self.fs, self.jdtls, self.ui)
  local spec = scaffold.wizard_spec(self.fs, self.jdtls, ctx)
  spec.preview = function(answers)
    local kind = scaffold.kind_by_id(self.fs, answers.kind)
    if not kind then
      return ""
    end
    local pkg = scaffold.resolve_package(ctx.package, answers.package)
    local name = answers.name
    if not name or name == "" then
      name = "Type"
    end
    return scaffold.render(kind, pkg, name)
  end
  self:_run_wizard(spec, function(answers)
    if not answers then
      return
    end
    local kind = scaffold.kind_by_id(self.fs, answers.kind)
    local name = answers.name and answers.name:match("^%s*(.-)%s*$") or ""
    if not kind then
      return
    end
    if name == "" then
      self.ui:notify("Type name is required.")
      return
    end
    if not name:match("^[A-Za-z_][A-Za-z0-9_]*$") then
      self.ui:notify("Type name is not a valid Java identifier.")
      return
    end
    local pkg = scaffold.resolve_package(ctx.package, answers.package)
    local path = scaffold.path(ctx.root, pkg, name)
    if self.fs.exists and self.fs:exists(path) then
      self.ui:notify(name .. " already exists.")
      return
    end
    self.fs:write(path, scaffold.render(kind, pkg, name))
    if self.ui.open_file then
      self.ui:open_file(path)
    end
  end)
end

function Actions:packages()
  if not self:_gate() then
    return
  end
  self.ui:package_view(package_view.build(self.fs, self.jdtls))
end

function Actions:_reload_project()
  local jdtls = self.jdtls
  if jdtls and jdtls.refresh and jdtls.is_present and jdtls:is_present() then
    jdtls:refresh()
  end
end

local function is_import_line(line)
  return line:match("^%s*import%s") ~= nil
end

local function replace_range_with_simple(source, range, fqcn)
  if not range or range.lnum == nil then
    return source
  end
  local lines = split_lines(source)
  local i = range.lnum + 1
  local line = lines[i]
  if not line or is_import_line(line) then
    return source
  end
  local name = simple_name(fqcn)
  local col = range.col or 0
  local end_col = range.end_col or #line
  lines[i] = line:sub(1, col) .. name .. line:sub(end_col + 1)
  return table.concat(lines, "\n")
end

local function ensure_import(source, fqcn)
  local stmt = "import " .. fqcn .. ";"
  if source:find(stmt, 1, true) then
    return source
  end
  local lines = split_lines(source)
  local package_at, last_import
  for i, line in ipairs(lines) do
    if line:match("^%s*package%s") then
      package_at = i
    elseif line:match("^%s*import%s") then
      last_import = i
    end
  end
  local at
  if last_import then
    at = last_import + 1
  elseif package_at then
    at = package_at + 1
    if lines[at] == "" then
      at = at + 1
    else
      table.insert(lines, at, "")
      at = at + 1
    end
  else
    table.insert(lines, 1, "")
    table.insert(lines, 1, stmt)
    return table.concat(lines, "\n")
  end
  table.insert(lines, at, stmt)
  if lines[at + 1] ~= "" then
    table.insert(lines, at + 1, "")
  end
  return table.concat(lines, "\n")
end

function Actions:_read_java(path)
  if self.ui and self.ui.read_buffer then
    local buf = self.ui:read_buffer(path)
    if buf then
      return buf
    end
  end
  if self.fs then
    return self.fs:read(path)
  end
end

function Actions:_write_java(path, content)
  self.fs:write(path, content)
  if self.ui and self.ui.edit_buffer then
    self.ui:edit_buffer(path, content)
  end
end

function Actions:_fix_java_buffer(action, hit)
  if not action or not action.file or not self.fs then
    return
  end
  local fqcn = action.query
  if not (fqcn and fqcn:find(".", 1, true)) then
    fqcn = hit and hit.fqcn
  end
  if not (fqcn and fqcn:find(".", 1, true)) then
    return
  end
  local source = self:_read_java(action.file)
  if not source then
    return
  end
  local next_src = replace_range_with_simple(source, action.range, fqcn)
  next_src = ensure_import(next_src, fqcn)
  if next_src ~= source then
    self:_write_java(action.file, next_src)
  end
end

function Actions:_add_dependency_query(query, opts)
  opts = opts or {}
  if not self:_gate() then
    return
  end
  query = query and query:match("^%s*(.-)%s*$") or ""
  if query == "" then
    return
  end

  local pom = self.fs:read("pom.xml")
  if not dependency.parseable(pom) then
    self.ui:notify("pom.xml is missing or invalid.")
    return
  end

  if not self.central then
    self.ui:notify("Maven Central search failed.")
    return
  end

  local hits, err, kind = dependency.search(self.central, query)
  if err then
    self.ui:notify("Maven Central search failed.")
    return
  end
  if not hits or #hits == 0 then
    self.ui:notify("No artifacts found.")
    return
  end

  local function apply(hit)
    if not hit then
      return
    end
    if not dependency.has_gav(pom, hit.g, hit.a) then
      local omit_version = dependency.is_managed(pom, hit.g, hit.a, self.central)
      local scope
      if not opts.ignore_buffer and self.ui.current_file then
        scope = dependency.test_scope(self.ui:current_file())
      end
      local next_pom = dependency.insert(pom, hit, {
        omit_version = omit_version,
        scope = scope,
      })
      if not next_pom then
        self.ui:notify("pom.xml is missing or invalid.")
        return
      end
      self.fs:write("pom.xml", next_pom)
    end
    self:_fix_java_buffer(opts.action, hit)
    self:_reload_project()
  end

  if dependency.should_auto_apply(kind, hits) then
    apply(dependency.unique_gav(hits))
    return
  end
  if self.ui.pick then
    self.ui:pick(hits, apply)
  end
end

function Actions:code_actions(ctx)
  ctx = ctx or {}
  local jdtls = self.jdtls
  if not jdtls or not jdtls.is_running or not jdtls:is_running() then
    return {}
  end

  local file = ctx.file
  if not file and self.ui and self.ui.current_file then
    file = self.ui:current_file()
  end
  if not file then
    return {}
  end

  local diags = ctx.diagnostics
  if not diags and jdtls.diagnostics then
    diags = jdtls:diagnostics(file)
  end
  diags = diags or {}

  local source = ctx.source or self:_read_java(file) or ""

  local offered = {}
  for _, diag in ipairs(diags) do
    local type_text = range_text(source, diag)
    if overlaps_cursor(ctx, diag) and is_unresolved_type(diag, type_text) then
      local name = simple_name(type_text)
      offered[#offered + 1] = {
        title = "Resolve unknown type '" .. name .. "'",
        kind = "quickfix",
        query = type_text,
        file = file,
        range = {
          lnum = diag.lnum,
          col = diag.col,
          end_lnum = diag.end_lnum or diag.lnum,
          end_col = diag.end_col,
        },
      }
      break
    end
  end
  return offered
end

function Actions:add_dependency(query, opts)
  if not self:_gate() then
    return
  end
  opts = opts or {}
  query = query and query:match("^%s*(.-)%s*$") or ""
  if query == "" then
    if self.ui.input then
      query = self.ui:input("Dependency: ") or ""
    end
    query = query:match("^%s*(.-)%s*$") or ""
  end
  self:_add_dependency_query(query, opts)
end

function Actions:apply_code_action(action)
  if not action or not action.query then
    return
  end
  self:_add_dependency_query(action.query, { action = action })
end

function Actions:_maven_run_argv()
  if self.fs:exists("mvnw") then
    return { "./mvnw", "spring-boot:run" }
  end
  if self.host and self.host.has and self.host:has("mvn") then
    return { "mvn", "spring-boot:run" }
  end
  return nil
end

function Actions:_has_devtools(pom)
  if not pom or not dependency.has_gav(pom, "org.springframework.boot", "spring-boot-devtools") then
    return false
  end
  for dep in pom:gmatch("<dependency[^>]*>(.-)</dependency>") do
    if
      dep:find("<groupId>%s*org%.springframework%.boot%s*</groupId>")
      and dep:find("<artifactId>%s*spring%-boot%-devtools%s*</artifactId>")
      and not dep:find("<scope>%s*test%s*</scope>")
    then
      return true
    end
  end
  return false
end

function Actions:run()
  if not self:_gate() then
    return
  end
  if not workspace.is_spring_boot(self.fs) then
    self.ui:notify("Not a Spring Boot project.")
    return
  end
  local argv = self:_maven_run_argv()
  if not argv or not self.host or not self.host.start then
    self.ui:notify("Neither mvnw nor mvn is available.")
    return
  end
  if self._boot_process then
    self.ui:notify("Spring Boot is already running.")
    return
  end
  self._boot_process = self.host:start(argv, { cwd = self.fs:cwd() })
  local pom = self.fs:read("pom.xml")
  if not self:_has_devtools(pom) then
    self.ui:notify("Reload will not happen without spring-boot-devtools.")
    if self.ui.confirm and self.ui:confirm("Add spring-boot-devtools so Reload can happen?") then
      self:add_dependency("org.springframework.boot:spring-boot-devtools", { ignore_buffer = true })
    end
  end
end

function Actions:stop()
  if not self:_gate() then
    return
  end
  if self._boot_process and self.host and self.host.stop then
    self.host:stop(self._boot_process)
    self._boot_process = nil
  end
end

return Actions

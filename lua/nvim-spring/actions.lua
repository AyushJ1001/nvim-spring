local workspace = require("nvim-spring.workspace")
local package_view = require("nvim-spring.package_view")
local dependency = require("nvim-spring.dependency")

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

function Actions:create()
  self:_gate()
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

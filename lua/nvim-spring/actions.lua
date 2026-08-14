local workspace = require("nvim-spring.workspace")
local package_view = require("nvim-spring.package_view")
local dependency = require("nvim-spring.dependency")
local scaffold = require("nvim-spring.scaffold")
local initializr = require("nvim-spring.initializr")

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
  self.http = adapters.http
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

function Actions:_refuse(message)
  if self.ui and self.ui.notify then
    self.ui:notify(message)
  end
end

function Actions:_initializr_url()
  return self.opts.initializr_url or "https://start.spring.io"
end

function Actions:_fetch_metadata()
  if not self.http or not self.http.request then
    return nil, "Initializr is unreachable."
  end
  local res = self.http:request({
    url = self:_initializr_url(),
    headers = initializr.headers(),
  })
  if not res or res.error then
    return nil, "Initializr is unreachable."
  end
  if res.status == 401 or res.status == 403 then
    return nil, "Initializr returned " .. tostring(res.status) .. "."
  end
  if res.status ~= 200 then
    return nil, "Initializr is unreachable."
  end
  if not initializr.is_metadata(res.body) then
    return nil, "Response is not Initializr metadata."
  end
  return res.body
end

function Actions:_host_jdk_major()
  if not self.host or not self.host.jdk_major then
    return nil
  end
  return self.host:jdk_major()
end

function Actions:_join(root, rel)
  if not rel or rel == "" then
    return root
  end
  if rel:sub(1, 1) == "/" then
    return rel
  end
  return root .. "/" .. rel
end

function Actions:_generate(meta, answers)
  local maven_type = initializr.maven_project_type(meta)
  local artifact = answers.artifactId or "demo"
  if artifact == "" or artifact == "." or artifact == ".." or artifact:find("[/\\]") then
    self:_refuse("Artifact name is not valid.")
    return
  end
  local cwd = self.fs and self.fs.cwd and self.fs:cwd() or ""
  if cwd == "" then
    self:_refuse("Could not resolve the current directory.")
    return
  end
  local dest = self:_join(cwd, artifact)
  if self.fs and self.fs.exists and self.fs:exists(dest) then
    self:_refuse(artifact .. " already exists.")
    return
  end
  local deps = initializr.dependency_query(answers.dependencies)
  local url = initializr.starter_url(self:_initializr_url(), {
    type = maven_type,
    groupId = answers.groupId,
    artifactId = artifact,
    name = artifact,
    packageName = answers.packageName,
    bootVersion = answers.bootVersion,
    javaVersion = answers.javaVersion,
    dependencies = deps,
    language = "java",
  })
  local res = self.http:request({
    url = url,
    headers = {
      ["User-Agent"] = initializr.USER_AGENT,
    },
  })
  if not res or res.error or res.status ~= 200 or res.body == nil then
    self:_refuse("Initializr is unreachable.")
    return
  end
  if not self.fs or not self.fs.extract_zip then
    self:_refuse("Could not unzip the project.")
    return
  end
  local ok = self.fs:extract_zip(res.body, dest)
  if not ok then
    self:_refuse("Could not unzip the project.")
    return
  end
  if self.ui and self.ui.open_project then
    self.ui:open_project(dest)
  end
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

-- Initializr does not need the workspace Build tool.
function Actions:init()
  local meta, err = self:_fetch_metadata()
  if not meta then
    self:_refuse(err)
    return
  end
  if not initializr.maven_project_type(meta) then
    self:_refuse("Initializr has no Maven project type.")
    return
  end
  local defaults = {
    boot = initializr.default_boot(meta),
    java = initializr.default_java(meta, self:_host_jdk_major()),
  }
  local spec = initializr.wizard_spec(meta, defaults, self:_initializr_url())
  spec.preview = function(state)
    return initializr.preview(state)
  end
  self:_run_wizard(spec, function(answers)
    if not answers then
      return
    end
    self:_generate(meta, answers)
  end)
end

function Actions:_gate()
  local verdict = workspace.classify(self.fs)
  if verdict.refuse then
    self.ui:notify(verdict.message)
    return false
  end
  return true
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

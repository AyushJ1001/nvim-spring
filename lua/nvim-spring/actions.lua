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

function Actions:setup(opts)
  self:_merge_opts(opts)
  self:_bind_keymaps()
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

function Actions:add_dependency(query)
  if not self:_gate() then
    return
  end
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
      if self.ui.current_file then
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

function Actions:run()
  self:_gate()
end

function Actions:stop()
  self:_gate()
end

return Actions

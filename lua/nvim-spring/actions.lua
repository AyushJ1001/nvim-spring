local workspace = require("nvim-spring.workspace")

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
  self:_gate()
end

function Actions:add_dependency()
  self:_gate()
end

function Actions:run()
  self:_gate()
end

function Actions:stop()
  self:_gate()
end

return Actions

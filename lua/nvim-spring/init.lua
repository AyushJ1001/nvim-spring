local actions = require("nvim-spring.actions")

local M = {}
local current
local did_setup = false

local function production()
  return require("nvim-spring.adapters").production()
end

local function instance()
  if not current then
    current = actions.new(production())
  end
  return current
end

function M.setup(opts)
  current = actions.new(production())
  current:setup(opts)
  did_setup = true
  return M
end

function M.ensure_setup()
  if not did_setup then
    M.setup({})
  end
end

function M.ensure_jdtls()
  M.ensure_setup()
  instance():ensure_jdtls()
end

local methods = { "init", "create", "packages", "add_dependency", "run", "stop" }
for _, name in ipairs(methods) do
  M[name] = function(...)
    M.ensure_setup()
    local plugin = instance()
    return plugin[name](plugin, ...)
  end
end

return M

if vim.g.loaded_nvim_spring then
  return
end
vim.g.loaded_nvim_spring = true

local commands = {
  SpringInit = "init",
  SpringCreate = "create",
  SpringPackages = "packages",
  SpringAddDependency = "add_dependency",
  SpringRun = "run",
  SpringStop = "stop",
}

for name, method in pairs(commands) do
  local opts = {}
  if name == "SpringAddDependency" then
    opts.nargs = "?"
  end
  vim.api.nvim_create_user_command(name, function(cmd)
    local fn = require("nvim-spring")[method]
    if cmd.args and cmd.args ~= "" then
      fn(cmd.args)
    else
      fn()
    end
  end, opts)
end

-- Let lang.java / the user's nvim-jdtls config start first; fill in only if none is up.
vim.api.nvim_create_autocmd("FileType", {
  pattern = "java",
  group = vim.api.nvim_create_augroup("nvim_spring_jdtls", { clear = true }),
  callback = function()
    vim.schedule(function()
      require("nvim-spring").ensure_jdtls()
    end)
  end,
})

local M = {}

function M:is_present()
  local ok = pcall(require, "jdtls")
  return ok
end

function M:is_running()
  if not vim.lsp or not vim.lsp.get_clients then
    return false
  end
  local clients = vim.lsp.get_clients({ name = "jdtls" })
  return clients ~= nil and #clients > 0
end

function M:start()
  local ok, jdtls = pcall(require, "jdtls")
  if not ok then
    return
  end
  local markers = {
    "pom.xml",
    "build.gradle",
    "build.gradle.kts",
    "settings.gradle",
    "settings.gradle.kts",
    ".git",
  }
  local root = (vim.fs and vim.fs.root(0, markers)) or vim.fn.getcwd()
  -- Minimal start: no on_attach keybinds, no DAP.
  pcall(jdtls.start_or_attach, {
    cmd = { "jdtls" },
    root_dir = root,
  })
end

return M

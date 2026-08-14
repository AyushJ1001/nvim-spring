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
  -- Minimal start: no on_attach keybinds, no DAP, no Microsoft JDT-LS bundle.
  pcall(jdtls.start_or_attach, {
    cmd = { "jdtls" },
    root_dir = root,
  })
end

local function unwrap_source_paths(result)
  if type(result) ~= "table" then
    return nil
  end
  if type(result.data) == "table" then
    return result.data
  end
  if result.result then
    return unwrap_source_paths(result.result)
  end
  if result[1] and (result[1].path or result[1].displayPath) then
    return result
  end
  return nil
end

function M:list_source_paths()
  if not self:is_running() then
    return nil
  end
  local clients = vim.lsp.get_clients({ name = "jdtls" })
  local client = clients and clients[1]
  if not client or not client.request_sync then
    return nil
  end
  local ok, resp = pcall(function()
    return client:request_sync("workspace/executeCommand", {
      command = "java.project.listSourcePaths",
      arguments = {},
    }, 3000)
  end)
  if not ok or type(resp) ~= "table" or resp.err then
    return nil
  end
  return unwrap_source_paths(resp.result)
end

function M:refresh()
  local ok, jdtls = pcall(require, "jdtls")
  if not ok then
    return
  end
  if jdtls.update_projects_config then
    pcall(jdtls.update_projects_config, { select_mode = "all" })
  elseif jdtls.update_project_config then
    pcall(jdtls.update_project_config)
  end
end

return M

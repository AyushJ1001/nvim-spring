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

function M:compile(kind)
  local ok, jdtls = pcall(require, "jdtls")
  if not ok or not jdtls.compile then
    return
  end
  pcall(jdtls.compile, kind or "incremental")
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

local function utf8_step(s, i)
  local b = s:byte(i)
  if not b then
    return nil
  end
  local nbytes, units
  if b < 0x80 then
    nbytes, units = 1, 1
  elseif b < 0xE0 then
    nbytes, units = 2, 1
  elseif b < 0xF0 then
    nbytes, units = 3, 1
  else
    nbytes, units = 4, 2
  end
  if i + nbytes - 1 > #s then
    return 1, 1
  end
  return nbytes, units
end

-- vim.diagnostic columns are 0-based bytes; the action module uses UTF-16.
local function byte_to_utf16(s, byte_off)
  if not s or byte_off <= 0 then
    return 0
  end
  local i, units = 1, 0
  local limit = byte_off + 1
  while i < limit and i <= #s do
    local nbytes, u16 = utf8_step(s, i)
    if not nbytes then
      break
    end
    units = units + u16
    i = i + nbytes
  end
  return units
end

function M:diagnostics(path)
  if not vim.diagnostic or not vim.diagnostic.get then
    return {}
  end
  local bufnr = 0
  if path and path ~= "" then
    bufnr = vim.fn.bufnr(path)
    if bufnr == -1 then
      return {}
    end
  end
  local diags = vim.diagnostic.get(bufnr)
  if not vim.api or not vim.api.nvim_buf_get_lines then
    return diags
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local out = {}
  for _, d in ipairs(diags) do
    local line = lines[(d.lnum or 0) + 1] or ""
    local copy = {}
    for k, v in pairs(d) do
      copy[k] = v
    end
    copy.col = byte_to_utf16(line, d.col or 0)
    if d.end_col then
      copy.end_col = byte_to_utf16(line, d.end_col)
    end
    out[#out + 1] = copy
  end
  return out
end

return M

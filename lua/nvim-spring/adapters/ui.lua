local M = {}

function M:notify(message, level)
  vim.notify(message, level or vim.log.levels.WARN)
end

function M:keymap(mode, lhs, rhs)
  vim.keymap.set(mode, lhs, rhs, { silent = true, desc = "nvim-spring" })
end

local PACKAGE_VIEW_FT = "nvim-spring-packages"

local function find_package_view_buf()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].filetype == PACKAGE_VIEW_FT then
      return bufnr
    end
  end
end

local function render_package_view(model)
  local lines = { model.name or "project" }
  local nodes = { false }
  if not model.roots or #model.roots == 0 then
    lines[#lines + 1] = "  (no source roots)"
    nodes[#nodes + 1] = false
    return lines, nodes
  end
  for _, root in ipairs(model.roots) do
    lines[#lines + 1] = "  " .. root.path
    nodes[#nodes + 1] = { root = root.path, package = "" }
    for _, pkg in ipairs(root.packages or {}) do
      local label = pkg
      if label == "" then
        label = "(default package)"
      end
      lines[#lines + 1] = "    " .. label
      nodes[#nodes + 1] = { root = root.path, package = pkg }
    end
  end
  return lines, nodes
end

local function show_package_view(bufnr)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == bufnr then
      vim.api.nvim_set_current_win(win)
      return
    end
  end
  vim.cmd("topleft 36vsplit")
  vim.api.nvim_win_set_buf(0, bufnr)
  vim.wo.number = false
  vim.wo.relativenumber = false
  vim.wo.signcolumn = "no"
  vim.wo.wrap = false
  vim.wo.winfixwidth = true
end

function M:package_view(model)
  local bufnr = find_package_view_buf()
  if not bufnr then
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[bufnr].buftype = "nofile"
    vim.bo[bufnr].bufhidden = "hide"
    vim.bo[bufnr].swapfile = false
    vim.bo[bufnr].filetype = PACKAGE_VIEW_FT
    pcall(vim.api.nvim_buf_set_name, bufnr, "Spring Packages")
    vim.keymap.set("n", "q", "<cmd>close<cr>", {
      buffer = bufnr,
      silent = true,
      nowait = true,
      desc = "Close Package view",
    })
  end
  local lines, nodes = render_package_view(model or {})
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].modified = false
  vim.b[bufnr].spring_nodes = nodes
  show_package_view(bufnr)
end

function M:package_view_selection()
  local bufnr = vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].filetype ~= PACKAGE_VIEW_FT then
    return nil
  end
  local nodes = vim.b[bufnr].spring_nodes
  if not nodes then
    return nil
  end
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local node = nodes[line]
  if node then
    return node
  end
  for _, entry in ipairs(nodes) do
    if entry then
      return entry
    end
  end
end

function M:wizard(spec, on_done)
  return require("nvim-spring.adapters.wizard").run(spec, on_done)
end

function M:open_file(path)
  vim.cmd.edit(vim.fn.fnameescape(path))
end

function M:input(prompt)
  local ok, result = pcall(vim.fn.input, prompt)
  if not ok then
    return nil
  end
  return result
end

function M:pick(items, cb)
  local labels = {}
  local by_label = {}
  for i, item in ipairs(items or {}) do
    local label = item.label or item.g .. ":" .. item.a
    labels[i] = label
    by_label[label] = item
  end
  vim.ui.select(labels, { prompt = "Add Dependency" }, function(choice)
    if cb then
      cb(choice and by_label[choice] or nil)
    end
  end)
end

function M:current_file()
  return vim.api.nvim_buf_get_name(0)
end

function M:read_buffer(path)
  local bufnr = vim.fn.bufnr(path)
  if bufnr == -1 or not vim.api.nvim_buf_is_loaded(bufnr) then
    return nil
  end
  return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
end

function M:edit_buffer(path, content)
  local bufnr = vim.fn.bufnr(path)
  if bufnr == -1 or not vim.api.nvim_buf_is_loaded(bufnr) then
    return false
  end
  local lines = vim.split(content, "\n", { plain = true })
  local last = lines[#lines]
  if last == "" then
    lines[#lines] = nil
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return true
end

local CODE_ACTION_CMD = "nvim-spring.apply_code_action"
local CLIENT_NAME = "nvim-spring"

local function to_lsp_actions(actions)
  local out = {}
  for _, action in ipairs(actions or {}) do
    out[#out + 1] = {
      title = action.title,
      kind = action.kind or "quickfix",
      command = {
        title = action.title,
        command = CODE_ACTION_CMD,
        arguments = { action },
      },
    }
  end
  return out
end

local function bufnr_for_params(params, fallback)
  local uri = params and params.textDocument and params.textDocument.uri
  if uri and vim.uri_to_fname then
    local nr = vim.fn.bufnr(vim.uri_to_fname(uri))
    if nr ~= -1 then
      return nr
    end
  end
  return fallback
end

local function ctx_from_params(params, bufnr)
  bufnr = bufnr_for_params(params, bufnr)
  local path = vim.api.nvim_buf_get_name(bufnr)
  if params and params.textDocument and params.textDocument.uri and vim.uri_to_fname then
    path = vim.uri_to_fname(params.textDocument.uri)
  end
  local source = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
  local ctx = { file = path, source = source }
  if params and params.range and params.range.start then
    ctx.lnum = params.range.start.line
    ctx.col = params.range.start.character
  end
  local raw = params and params.context and params.context.diagnostics
  if raw and #raw > 0 then
    local diags = {}
    for _, d in ipairs(raw) do
      local range = d.range or {}
      local start = range.start or {}
      local finish = range["end"] or start
      diags[#diags + 1] = {
        file = path,
        code = d.code,
        lnum = start.line or 0,
        col = start.character or 0,
        end_lnum = finish.line or start.line or 0,
        end_col = finish.character,
      }
    end
    ctx.diagnostics = diags
  end
  return ctx
end

local function already_attached(bufnr)
  if not vim.lsp or not vim.lsp.get_clients then
    return false
  end
  local clients = vim.lsp.get_clients({ bufnr = bufnr, name = CLIENT_NAME })
  return clients ~= nil and #clients > 0
end

local function jdtls_attached(bufnr)
  if not vim.lsp or not vim.lsp.get_clients then
    return false
  end
  local clients = vim.lsp.get_clients({ bufnr = bufnr, name = "jdtls" })
  return clients ~= nil and #clients > 0
end

function M:register_code_actions(list_fn, apply_fn)
  if not vim or not vim.lsp or not vim.lsp.start then
    return
  end

  vim.lsp.commands = vim.lsp.commands or {}
  vim.lsp.commands[CODE_ACTION_CMD] = function(command)
    local arg = command and command.arguments and command.arguments[1]
    if apply_fn then
      apply_fn(arg)
    end
  end

  local function attach(bufnr)
    if already_attached(bufnr) then
      return
    end
    vim.lsp.start({
      name = CLIENT_NAME,
      offset_encoding = "utf-16",
      root_dir = vim.fn.getcwd(),
      cmd = function()
        return {
          request = function(method, params, callback)
            if method == "initialize" then
              callback(nil, {
                capabilities = {
                  codeActionProvider = {
                    codeActionKinds = { "quickfix" },
                  },
                },
              })
            elseif method == "textDocument/codeAction" then
              callback(nil, to_lsp_actions(list_fn(ctx_from_params(params, bufnr))))
            elseif method == "workspace/executeCommand" then
              if params and params.command == CODE_ACTION_CMD and apply_fn then
                apply_fn(params.arguments and params.arguments[1])
              end
              callback(nil, nil)
            elseif method == "shutdown" then
              callback(nil, nil)
            else
              callback()
            end
          end,
          notify = function() end,
          is_closing = function()
            return false
          end,
          terminate = function() end,
        }
      end,
    }, { bufnr = bufnr })
  end

  local function maybe_attach(bufnr)
    if not vim.api.nvim_buf_is_loaded(bufnr) then
      return
    end
    if vim.bo[bufnr].filetype ~= "java" then
      return
    end
    if not jdtls_attached(bufnr) then
      return
    end
    attach(bufnr)
  end

  local group = vim.api.nvim_create_augroup("nvim_spring_code_actions", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "java",
    group = group,
    callback = function(ev)
      maybe_attach(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function(ev)
      local id = ev.data and ev.data.client_id
      local client = id and vim.lsp.get_client_by_id(id)
      if client and client.name == "jdtls" then
        maybe_attach(ev.buf)
      end
    end,
  })
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    maybe_attach(bufnr)
  end
end

function M:confirm(message)
  local ok, result = pcall(vim.fn.confirm, message, "&Yes\n&No", 2)
  if not ok then
    return false
  end
  return result == 1
end

function M:on_write(cb)
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = vim.api.nvim_create_augroup("nvim_spring_compile_on_save", { clear = true }),
    callback = function(ev)
      cb(ev.file ~= "" and ev.file or ev.match)
    end,
  })
end

function M:open_project(path)
  vim.cmd.cd(vim.fn.fnameescape(path))
  local pom = path .. "/pom.xml"
  local stat = (vim.uv and vim.uv.fs_stat(pom)) or (vim.loop and vim.loop.fs_stat(pom))
  if stat then
    vim.cmd.edit(vim.fn.fnameescape(pom))
  else
    vim.cmd.edit(vim.fn.fnameescape(path))
  end
end

return M


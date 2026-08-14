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


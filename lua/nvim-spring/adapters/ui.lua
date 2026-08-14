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
  if not model.roots or #model.roots == 0 then
    lines[#lines + 1] = "  (no source roots)"
    return lines
  end
  for _, root in ipairs(model.roots) do
    lines[#lines + 1] = "  " .. root.path
    for _, pkg in ipairs(root.packages or {}) do
      local label = pkg
      if label == "" then
        label = "(default package)"
      end
      lines[#lines + 1] = "    " .. label
    end
  end
  return lines
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
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, render_package_view(model or {}))
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].modified = false
  show_package_view(bufnr)
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

return M

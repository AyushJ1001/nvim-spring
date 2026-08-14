-- Preview-led Wizard. Narrow columns drop the preview.

local M = {}

local NARROW_COLUMNS = 100

local function copy_defaults(spec)
  local answers = {}
  for _, step in ipairs(spec.steps or {}) do
    for _, field in ipairs(step.fields or {}) do
      answers[field.name] = field.default
    end
  end
  return answers
end

local function field_label(value)
  if type(value) == "table" then
    return value.name or value.id or ""
  end
  return tostring(value)
end

local function field_id(value)
  if type(value) == "table" then
    return value.id
  end
  return value
end

local function field_type(field)
  if field.type then
    return field.type
  end
  if field.values then
    return "select"
  end
  return "text"
end

function M.run(spec, on_done)
  spec = spec or {}
  local answers = copy_defaults(spec)
  local step_i = 1
  local cursor = 1
  local filter = ""
  local drop_preview = vim.o.columns < NARROW_COLUMNS

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  pcall(vim.api.nvim_buf_set_name, buf, "nvim-spring://wizard")

  local width = math.min(vim.o.columns - 4, drop_preview and 72 or 96)
  local height = math.min(vim.o.lines - 6, drop_preview and 22 or 26)
  local row = math.max(1, math.floor((vim.o.lines - height) / 2) - 1)
  local col = math.max(0, math.floor((vim.o.columns - width) / 2))

  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = spec.title or "Wizard",
    title_pos = "left",
    zindex = 50,
  }
  local opened, win = pcall(vim.api.nvim_open_win, buf, true, win_opts)
  if not opened then
    win_opts.title = nil
    win_opts.title_pos = nil
    win = vim.api.nvim_open_win(buf, true, win_opts)
  end

  local finished = false

  local function close()
    if win and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
    if buf and vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end

  local function finish(result)
    if finished then
      return
    end
    finished = true
    close()
    if on_done then
      on_done(result)
    end
  end

  local function step()
    return spec.steps[step_i]
  end

  local function current_field()
    local current = step()
    return current and current.fields and current.fields[1]
  end

  local function listed_values(field)
    local values = {}
    for _, value in ipairs(field.values or {}) do
      values[#values + 1] = value
    end
    if filter ~= "" then
      local q = filter:lower()
      local filtered = {}
      for _, value in ipairs(values) do
        local hay = (field_label(value) .. " " .. tostring(field_id(value) or "") .. " " .. tostring(value.description or "")):lower()
        if hay:find(q, 1, true) then
          filtered[#filtered + 1] = value
        end
      end
      values = filtered
    end
    if field.allow_new and filter ~= "" then
      local exists = false
      for _, value in ipairs(field.values or {}) do
        if field_id(value) == filter or field_label(value) == filter then
          exists = true
          break
        end
      end
      if not exists then
        values[#values + 1] = {
          id = filter,
          name = filter,
          description = field.new_label or "new",
        }
      end
    end
    return values
  end

  local function render()
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    local current = step()
    local field = current_field()
    local lines = {}
    local meta = (spec.source or "") .. " · step " .. step_i .. "/" .. #spec.steps
    lines[#lines + 1] = (spec.title or "Wizard") .. "  " .. meta

    local chrome = {}
    for i, s in ipairs(spec.steps) do
      local mark = i .. " " .. s.title
      if i == step_i then
        mark = "[" .. mark .. "]"
      end
      chrome[#chrome + 1] = mark
    end
    lines[#lines + 1] = table.concat(chrome, "  ·  ")
    lines[#lines + 1] = ""

    local preview_lines = {}
    if not drop_preview and spec.preview then
      local text = spec.preview(answers) or ""
      for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        preview_lines[#preview_lines + 1] = line
      end
    end

    local body = {}
    if field and field_type(field) == "select" then
      body[#body + 1] = "filter: " .. filter
      local values = listed_values(field)
      if cursor > #values then
        cursor = math.max(1, #values)
      end
      for i, value in ipairs(values) do
        local id = field_id(value)
        local mark = answers[field.name] == id and "*" or " "
        local prefix = i == cursor and "> " or "  "
        local desc = value.description and ("  " .. value.description) or ""
        body[#body + 1] = prefix .. mark .. " " .. field_label(value) .. desc
      end
      if #values == 0 then
        body[#body + 1] = "  (no matches)"
      end
    elseif field then
      body[#body + 1] = "> " .. (current.title or field.label or field.name)
      body[#body + 1] = "  " .. tostring(answers[field.name] or "")
    end

    if drop_preview or #preview_lines == 0 then
      for _, line in ipairs(body) do
        lines[#lines + 1] = line
      end
    else
      local left_w = math.floor(width * 0.48)
      local rows = math.max(#preview_lines, #body)
      lines[#lines + 1] = "LIVE PREVIEW" .. string.rep(" ", math.max(1, left_w - 12)) .. "│"
      for i = 1, rows do
        local left = preview_lines[i] or ""
        if #left > left_w - 1 then
          left = left:sub(1, left_w - 2) .. "…"
        end
        left = left .. string.rep(" ", math.max(0, left_w - #left))
        lines[#lines + 1] = left .. "│ " .. (body[i] or "")
      end
    end

    lines[#lines + 1] = ""
    local last = step_i == #spec.steps
    lines[#lines + 1] = last and "enter create   e edit   esc back   q quit"
      or "enter next   / filter   esc back   q quit"

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
  end

  local function select_cursor()
    local field = current_field()
    if not field or field_type(field) ~= "select" then
      return
    end
    local values = listed_values(field)
    local value = values[cursor]
    if value then
      answers[field.name] = field_id(value)
    end
  end

  local function edit_text()
    local field = current_field()
    if not field then
      return
    end
    if field_type(field) == "text" then
      local value = vim.fn.input((step().title or field.name) .. ": ", tostring(answers[field.name] or ""))
      if value ~= nil then
        answers[field.name] = value
      end
    else
      filter = vim.fn.input("filter: ", filter)
      cursor = 1
    end
    render()
  end

  local function next_step()
    select_cursor()
    if step_i < #spec.steps then
      step_i = step_i + 1
      cursor = 1
      filter = ""
      render()
      local field = current_field()
      if field and field_type(field) == "text" then
        edit_text()
      end
      return
    end
    local field = current_field()
    if field and field_type(field) == "text" then
      local value = answers[field.name]
      if not value or value == "" then
        edit_text()
        value = answers[field.name]
      end
      if not value or value == "" then
        return
      end
    end
    finish(answers)
  end

  local function prev_step()
    if step_i > 1 then
      step_i = step_i - 1
      cursor = 1
      filter = ""
      render()
      return
    end
    finish(nil)
  end

  local function map(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true })
  end

  map("q", function()
    finish(nil)
  end)
  map("<Esc>", prev_step)
  map("<CR>", next_step)
  map("e", edit_text)
  map("i", edit_text)
  map("/", edit_text)
  map("j", function()
    local field = current_field()
    local max = 1
    if field and field_type(field) == "select" then
      max = math.max(1, #listed_values(field))
    end
    cursor = math.min(max, cursor + 1)
    select_cursor()
    render()
  end)
  map("k", function()
    cursor = math.max(1, cursor - 1)
    select_cursor()
    render()
  end)
  map("<Down>", function()
    vim.api.nvim_feedkeys("j", "m", false)
  end)
  map("<Up>", function()
    vim.api.nvim_feedkeys("k", "m", false)
  end)

  vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    buffer = buf,
    once = true,
    callback = function()
      if not finished then
        finish(nil)
      end
    end,
  })

  render()
  return nil
end

return M

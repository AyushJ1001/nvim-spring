-- Test-only adapters. Not a product seam.

local fakes = {}

local function join(root, rel)
  if not rel or rel == "" then
    return root
  end
  if rel:sub(1, 1) == "/" then
    return rel
  end
  return root .. "/" .. rel
end

function fakes.fs(opts)
  opts = opts or {}
  local root = opts.root or "/workspace"
  local files = {}
  if opts.files then
    for path, content in pairs(opts.files) do
      files[join(root, path)] = content
    end
  end
  local fs = {
    root = root,
    files = files,
    writes = {},
  }

  function fs:cwd()
    return root
  end

  function fs:read(path)
    return files[join(root, path)]
  end

  function fs:exists(path)
    return files[join(root, path)] ~= nil
  end

  function fs:write(path, content)
    local full = join(root, path)
    files[full] = content
    self.writes[#self.writes + 1] = full
  end

  return fs
end

function fakes.ui()
  return {
    notifications = {},
    keymaps = {},
    notify = function(self, message, level)
      self.notifications[#self.notifications + 1] = {
        message = message,
        level = level,
      }
    end,
    keymap = function(self, mode, lhs, rhs)
      self.keymaps[#self.keymaps + 1] = { mode = mode, lhs = lhs, rhs = rhs }
    end,
  }
end

function fakes.jdtls(opts)
  opts = opts or {}
  return {
    present = opts.present ~= false,
    running = opts.running == true,
    starts = 0,
    stops = 0,
    refreshes = 0,
    is_present = function(self)
      return self.present
    end,
    is_running = function(self)
      return self.running
    end,
    start = function(self)
      self.starts = self.starts + 1
      self.running = true
    end,
    stop = function(self)
      self.stops = self.stops + 1
      self.running = false
    end,
    refresh = function(self)
      self.refreshes = self.refreshes + 1
    end,
  }
end

function fakes.plugin(opts)
  opts = opts or {}
  local ui = opts.ui or fakes.ui()
  local jdtls = opts.jdtls or fakes.jdtls({ running = true, present = true })
  local fs = opts.fs or fakes.fs(opts)
  local actions = require("nvim-spring.actions")
  local plugin = actions.new({
    fs = fs,
    ui = ui,
    jdtls = jdtls,
    opts = opts.opts,
  })
  return plugin, { fs = fs, ui = ui, jdtls = jdtls }
end

function fakes.notify_text(ui)
  local parts = {}
  for _, n in ipairs(ui.notifications) do
    parts[#parts + 1] = n.message or ""
  end
  return table.concat(parts, "\n")
end

return fakes

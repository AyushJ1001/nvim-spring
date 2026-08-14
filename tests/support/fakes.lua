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
    local full = join(root, path)
    if files[full] ~= nil then
      return true
    end
    return self:is_dir(path)
  end

  function fs:is_dir(path)
    local full = join(root, path)
    if files[full] ~= nil then
      return false
    end
    local prefix = full .. "/"
    for name in pairs(files) do
      if name:sub(1, #prefix) == prefix then
        return true
      end
    end
    return false
  end

  function fs:list(path)
    local full = join(root, path)
    local prefix = full .. "/"
    local seen = {}
    local names = {}
    for name in pairs(files) do
      if name:sub(1, #prefix) == prefix then
        local rest = name:sub(#prefix + 1)
        local child = rest:match("^([^/]+)")
        if child and not seen[child] then
          seen[child] = true
          names[#names + 1] = child
        end
      end
    end
    table.sort(names)
    return names
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
    package_views = {},
    notify = function(self, message, level)
      self.notifications[#self.notifications + 1] = {
        message = message,
        level = level,
      }
    end,
    keymap = function(self, mode, lhs, rhs)
      self.keymaps[#self.keymaps + 1] = { mode = mode, lhs = lhs, rhs = rhs }
    end,
    package_view = function(self, model)
      self.package_views[#self.package_views + 1] = model
    end,
  }
end

function fakes.jdtls(opts)
  opts = opts or {}
  return {
    present = opts.present ~= false,
    running = opts.running == true,
    source_paths = opts.source_paths,
    starts = 0,
    stops = 0,
    refreshes = 0,
    list_source_path_calls = 0,
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
    list_source_paths = function(self)
      self.list_source_path_calls = self.list_source_path_calls + 1
      return self.source_paths
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

function fakes.last_package_view(ui)
  return ui.package_views[#ui.package_views]
end

return fakes

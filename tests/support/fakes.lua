-- Test-only adapters. Not a product seam.

local pathutil = require("nvim-spring.path")
local fakes = {}

local function join(root, rel)
  return pathutil.join(root, rel)
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

  function fs:mkdir() end

  function fs:write(path, content)
    local full = join(root, path)
    files[full] = content
    self.writes[#self.writes + 1] = full
  end

  function fs:extract_zip(archive, dest)
    dest = join(root, dest)
    if type(archive) ~= "table" then
      return false
    end
    local tree = archive.__nvim_spring_files or archive
    for rel, content in pairs(tree) do
      if rel ~= "__nvim_spring_files" then
        local full = dest .. "/" .. rel
        files[full] = content
        self.writes[#self.writes + 1] = full
      end
    end
    return true
  end

  return fs
end

function fakes.ui(opts)
  opts = opts or {}
  return {
    notifications = {},
    keymaps = {},
    package_views = {},
    wizards = {},
    opened = nil,
    pick_calls = 0,
    pick_items = nil,
    pick_choice = opts.pick_choice,
    input_text = opts.input_text,
    confirm_result = opts.confirm,
    file = opts.file,
    confirm_calls = 0,
    last_confirm = nil,
    write_handler = nil,
    selection = opts.selection,
    wizard_answers = opts.wizard_answers,
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
    input = function(self, prompt)
      self.last_input_prompt = prompt
      return self.input_text
    end,
    pick = function(self, items, cb)
      self.pick_calls = self.pick_calls + 1
      self.pick_items = items
      local choice = self.pick_choice
      if type(choice) == "function" then
        choice = choice(items)
      elseif type(choice) == "number" then
        choice = items and items[choice]
      end
      if cb then
        cb(choice)
      end
      return choice
    end,
    current_file = function(self)
      return self.file
    end,
    confirm = function(self, message)
      self.confirm_calls = self.confirm_calls + 1
      self.last_confirm = message
      return self.confirm_result == true
    end,
    on_write = function(self, cb)
      self.write_handler = cb
    end,
    fire_write = function(self, path)
      if self.write_handler then
        self.write_handler(path)
      end
    end,
    package_view_selection = function(self)
      return self.selection
    end,
    wizard = function(self, spec, cb)
      self.wizards[#self.wizards + 1] = spec
      local answers = self.wizard_answers
      if type(answers) == "function" then
        answers = answers(spec)
      end
      if answers == nil then
        answers = {}
        for _, step in ipairs(spec.steps or {}) do
          for _, field in ipairs(step.fields or {}) do
            answers[field.name] = field.default
          end
        end
      end
      if answers == false then
        if cb then
          cb(nil)
        end
        return false
      end
      if cb then
        cb(answers)
      end
      return answers
    end,
    open_file = function(self, path)
      self.opened = path
    end,
    open_project = function(self, path)
      self.opened = path
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
    compiles = 0,
    last_compile = nil,
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
    compile = function(self, kind)
      self.compiles = self.compiles + 1
      self.last_compile = kind
    end,
  }
end

function fakes.central(opts)
  opts = opts or {}
  local central = {
    docs = opts.docs or {},
    error = opts.error,
    poms = opts.poms or {},
  }

  local function search(self)
    if self.error then
      return nil, self.error
    end
    return self.docs
  end

  function central:search_coordinates()
    return search(self)
  end

  function central:search_class()
    return search(self)
  end

  function central:search_keyword()
    return search(self)
  end

  function central:fetch_pom(g, a, v)
    return self.poms[g .. ":" .. a .. ":" .. v]
      or self.poms[g .. ":" .. a]
      or self.poms.default
  end

  return central
end

function fakes.initializr_metadata(opts)
  opts = opts or {}
  return {
    groupId = { type = "text", default = opts.group or "com.example" },
    artifactId = { type = "text", default = opts.artifact or "demo" },
    packageName = { type = "text", default = opts.package or "com.example.demo" },
    bootVersion = {
      type = "single-select",
      default = opts.boot_default or "4.1.0",
      values = opts.boot_values or {
        { id = "4.1.1-SNAPSHOT", name = "4.1.1 (SNAPSHOT)" },
        { id = "4.1.0", name = "4.1.0" },
        { id = "4.0.7", name = "4.0.7" },
      },
    },
    javaVersion = {
      type = "single-select",
      default = opts.java_default or "17",
      values = opts.java_values or {
        { id = "25", name = "25" },
        { id = "21", name = "21" },
        { id = "17", name = "17" },
      },
    },
    type = {
      type = "action",
      default = opts.type_default or "gradle-project",
      values = opts.types or {
        {
          id = "gradle-project",
          name = "Gradle Project",
          tags = { build = "gradle", format = "project" },
        },
        {
          id = "maven-project",
          name = "Maven Project",
          tags = { build = "maven", format = "project" },
        },
      },
    },
    dependencies = {
      type = "hierarchical-multi-select",
      values = opts.dependencies or {
        {
          name = "Web",
          values = {
            { id = "web", name = "Spring Web", description = "MVC + Tomcat" },
            { id = "devtools", name = "Spring Boot DevTools", description = "automatic context restart" },
          },
        },
      },
    },
  }
end

function fakes.http(opts)
  opts = opts or {}
  local http = {
    requests = {},
    error = opts.error,
    status = opts.status,
    body = opts.body,
    archive = opts.archive,
    zip_status = opts.zip_status,
    zip_error = opts.zip_error,
  }

  function http:request(req, on_done)
    self.requests[#self.requests + 1] = req
    local url = req.url or ""
    local is_zip = url:find("starter.zip", 1, true)
    local res
    if is_zip then
      if self.zip_error then
        res = { error = self.zip_error }
      else
        res = {
          status = self.zip_status or 200,
          body = self.archive,
        }
      end
    elseif self.error then
      res = { error = self.error }
    else
      res = {
        status = self.status or 200,
        body = self.body,
      }
    end
    if on_done then
      on_done(res)
      return
    end
    return res
  end

  return http
end

function fakes.host(opts)
  opts = opts or {}
  local bins = opts.bins or { mvn = true }
  local host = {
    bins = bins,
    starts = {},
    stops = {},
    running = {},
    next_id = 1,
    jdk = opts.jdk_major,
  }

  function host:has(bin)
    return self.bins[bin] == true
  end

  function host:start(argv, start_opts)
    local handle = {
      id = self.next_id,
      argv = argv,
      opts = start_opts,
    }
    self.next_id = self.next_id + 1
    self.starts[#self.starts + 1] = handle
    self.running[handle.id] = handle
    return handle
  end

  function host:stop(handle)
    self.stops[#self.stops + 1] = handle
    if handle and handle.id then
      self.running[handle.id] = nil
    end
  end

  function host:jdk_major()
    return self.jdk
  end

  return host
end

function fakes.plugin(opts)
  opts = opts or {}
  local ui = opts.ui or fakes.ui(opts)
  local jdtls = opts.jdtls or fakes.jdtls({ running = true, present = true })
  local fs = opts.fs or fakes.fs(opts)
  local central = opts.central or fakes.central()
  local http = opts.http or fakes.http({ error = "unreachable" })
  local host = opts.host or fakes.host({ jdk_major = 21 })
  local actions = require("nvim-spring.actions")
  local plugin = actions.new({
    fs = fs,
    ui = ui,
    jdtls = jdtls,
    central = central,
    http = http,
    host = host,
    opts = opts.opts,
  })
  return plugin, { fs = fs, ui = ui, jdtls = jdtls, central = central, http = http, host = host }
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

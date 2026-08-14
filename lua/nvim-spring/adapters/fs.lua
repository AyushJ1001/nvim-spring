local M = {}

local function resolve(self, path)
  if path:sub(1, 1) == "/" then
    return path
  end
  return self:cwd() .. "/" .. path
end

function M:cwd()
  return vim.fn.getcwd()
end

function M:read(path)
  path = resolve(self, path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  return content
end

function M:exists(path)
  path = resolve(self, path)
  local stat = vim.uv and vim.uv.fs_stat(path) or (vim.loop and vim.loop.fs_stat(path))
  return stat ~= nil
end

function M:is_dir(path)
  path = resolve(self, path)
  local stat = vim.uv and vim.uv.fs_stat(path) or (vim.loop and vim.loop.fs_stat(path))
  return stat ~= nil and stat.type == "directory"
end

function M:list(path)
  path = resolve(self, path)
  local uv = vim.uv or vim.loop
  if not uv or not uv.fs_scandir then
    return {}
  end
  local handle = uv.fs_scandir(path)
  if not handle then
    return {}
  end
  local names = {}
  while true do
    local name = uv.fs_scandir_next(handle)
    if not name then
      break
    end
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

function M:mkdir(path)
  path = resolve(self, path)
  vim.fn.mkdir(path, "p")
end

function M:write(path, content)
  path = resolve(self, path)
  local dir = path:match("(.+)/[^/]+$")
  if dir then
    vim.fn.mkdir(dir, "p")
  end
  local f, err = io.open(path, "w")
  if not f then
    error(err)
  end
  f:write(content)
  f:close()
end

local function run(args)
  if vim.system then
    local result = vim.system(args, { text = true }):wait()
    return result.code == 0
  end
  local cmd = {}
  for _, arg in ipairs(args) do
    cmd[#cmd + 1] = vim.fn.shellescape(arg)
  end
  vim.fn.system(table.concat(cmd, " "))
  return vim.v.shell_error == 0
end

function M:extract_zip(archive, dest)
  dest = resolve(self, dest)
  local tmp = vim.fn.tempname() .. ".zip"
  local f, err = io.open(tmp, "wb")
  if not f then
    return false, err
  end
  f:write(archive)
  f:close()

  local ok = false
  if vim.fn.executable("unzip") == 1 then
    ok = run({ "unzip", "-o", "-q", tmp, "-d", dest })
  elseif vim.fn.executable("python3") == 1 then
    ok = run({ "python3", "-m", "zipfile", "-e", tmp, dest })
  end
  os.remove(tmp)
  if not ok then
    pcall(vim.fn.delete, dest, "d")
  end
  return ok
end

return M


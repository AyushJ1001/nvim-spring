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

function M:write(path, content)
  path = resolve(self, path)
  local f, err = io.open(path, "w")
  if not f then
    error(err)
  end
  f:write(content)
  f:close()
end

return M

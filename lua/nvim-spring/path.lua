-- Internal path helpers. Treat POSIX, Windows drive, and UNC paths as absolute.

local M = {}

function M.is_absolute(path)
  if not path or path == "" then
    return false
  end
  local first = path:sub(1, 1)
  if first == "/" or first == "\\" then
    return true
  end
  if path:match("^%a:[/\\]") then
    return true
  end
  return false
end

function M.join(root, rel)
  if not rel or rel == "" then
    return root
  end
  if M.is_absolute(rel) then
    return rel
  end
  if not root or root == "" then
    return rel
  end
  local sep = (root:find("\\") and not root:find("/")) and "\\" or "/"
  local last = root:sub(-1)
  if last == "/" or last == "\\" then
    return root .. rel
  end
  return root .. sep .. rel
end

return M

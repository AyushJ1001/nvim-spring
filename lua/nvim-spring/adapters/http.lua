local M = {}

local function decode_body(body, headers)
  local accept = headers and headers.Accept or ""
  if accept:find("json", 1, true) and vim.json and vim.json.decode then
    local ok, decoded = pcall(vim.json.decode, body)
    if ok then
      return decoded
    end
  end
  return body
end

local function run_curl(args)
  if vim.fn.executable("curl") ~= 1 then
    return nil
  end
  if vim.system then
    local result = vim.system(args, { text = true }):wait()
    return result
  end
  local cmd = {}
  for _, arg in ipairs(args) do
    cmd[#cmd + 1] = vim.fn.shellescape(arg)
  end
  local stdout = vim.fn.system(table.concat(cmd, " "))
  return {
    code = vim.v.shell_error,
    stdout = stdout,
    stderr = "",
  }
end

function M:request(opts)
  opts = opts or {}
  local tmp = vim.fn.tempname()
  local args = {
    "curl",
    "-sS",
    "-L",
    "--max-time",
    "60",
    "-o",
    tmp,
    "-w",
    "%{http_code}",
    "-g",
  }
  for name, value in pairs(opts.headers or {}) do
    args[#args + 1] = "-H"
    args[#args + 1] = name .. ": " .. value
  end
  args[#args + 1] = opts.url

  local result = run_curl(args)
  local body
  local file = io.open(tmp, "rb")
  if file then
    body = file:read("*a")
    file:close()
  end
  os.remove(tmp)

  if not result then
    return { error = "unreachable" }
  end
  local status = tonumber((result.stdout or ""):match("(%d%d%d)")) or 0
  if status == 0 then
    return { error = "unreachable" }
  end
  return {
    status = status,
    body = decode_body(body, opts.headers),
  }
end

return M

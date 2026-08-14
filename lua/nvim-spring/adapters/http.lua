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

local function finish(on_done, res)
  if not on_done then
    return
  end
  if vim.schedule then
    vim.schedule(function()
      on_done(res)
    end)
    return
  end
  on_done(res)
end

local function read_tmp(tmp)
  local file = io.open(tmp, "rb")
  if not file then
    return nil
  end
  local body = file:read("*a")
  file:close()
  os.remove(tmp)
  return body
end

local function to_response(stdout, body, headers)
  local status = tonumber((stdout or ""):match("(%d%d%d)")) or 0
  if status == 0 then
    return { error = "unreachable" }
  end
  return {
    status = status,
    body = decode_body(body, headers),
  }
end

function M:request(opts, on_done)
  opts = opts or {}
  if vim.fn.executable("curl") ~= 1 then
    finish(on_done, { error = "unreachable" })
    return
  end

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

  local function done(stdout)
    finish(on_done, to_response(stdout, read_tmp(tmp), opts.headers))
  end

  if vim.system then
    vim.system(args, { text = true }, function(result)
      done(result and result.stdout)
    end)
    return
  end

  local chunks = {}
  vim.fn.jobstart(args, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if data then
        chunks[#chunks + 1] = table.concat(data, "\n")
      end
    end,
    on_exit = function()
      done(table.concat(chunks))
    end,
  })
end

return M

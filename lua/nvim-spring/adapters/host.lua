local M = {}

function M:has(bin)
  return vim.fn.executable(bin) == 1
end

function M:start(argv, opts)
  opts = opts or {}
  vim.cmd("botright 15split")
  vim.cmd("enew")
  local bufnr = vim.api.nvim_get_current_buf()
  vim.bo[bufnr].bufhidden = "hide"
  pcall(vim.api.nvim_buf_set_name, bufnr, "Spring Run")
  local job_opts = { cwd = opts.cwd }
  local job_id
  if vim.fn.termopen then
    job_id = vim.fn.termopen(argv, job_opts)
  else
    job_opts.term = true
    job_id = vim.fn.jobstart(argv, job_opts)
  end
  return { id = job_id, bufnr = bufnr }
end

function M:stop(handle)
  if handle and handle.id and handle.id > 0 then
    pcall(vim.fn.jobstop, handle.id)
  end
end

local function host_jdk_output()
  if vim.fn.executable("java") ~= 1 then
    return nil
  end
  if vim.system then
    local result = vim.system({ "java", "-version" }, { text = true }):wait()
    return ((result.stderr or "") .. "\n" .. (result.stdout or ""))
  end
  return vim.fn.system("java -version 2>&1")
end

function M:jdk_major()
  local text = host_jdk_output()
  if not text then
    return nil
  end
  local quoted = text:match('version%s+"([^"]+)"')
  if not quoted then
    return nil
  end
  return require("nvim-spring.initializr").parse_language_level(quoted)
end

return M


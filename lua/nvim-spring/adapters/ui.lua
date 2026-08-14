local M = {}

function M:notify(message, level)
  vim.notify(message, level or vim.log.levels.WARN)
end

function M:keymap(mode, lhs, rhs)
  vim.keymap.set(mode, lhs, rhs, { silent = true, desc = "nvim-spring" })
end

return M

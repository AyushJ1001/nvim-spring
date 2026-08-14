local M = {}

function M.production()
  return {
    fs = require("nvim-spring.adapters.fs"),
    ui = require("nvim-spring.adapters.ui"),
    jdtls = require("nvim-spring.adapters.jdtls"),
    central = require("nvim-spring.adapters.central"),
    host = require("nvim-spring.adapters.host"),
  }
end

return M

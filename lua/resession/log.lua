local config = require("resession.config")
local log = require("plenary.log").new(
  vim.tbl_deep_extend("force", config.log, { plugin = "resession" }),
  false
)

return log

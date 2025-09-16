local config = require("resession.config")
local log = require("plenary.log").new(
  ---@diagnostic disable-next-line: param-type-not-match
  vim.tbl_deep_extend("force", config.log, { plugin = "resession" }),
  false
)

return log

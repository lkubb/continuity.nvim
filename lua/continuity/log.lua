---@class continuity.log
---@field trace fun(...: any)
---@field debug fun(...: any)
---@field info fun(...: any)
---@field warn fun(...: any)
---@field error fun(...: any)
---@field fatal fun(...: any)
---@field fmt_trace fun(fmt: string, ...: any)
---@field fmt_debug fun(fmt: string, ...: any)
---@field fmt_info fun(fmt: string, ...: any)
---@field fmt_warn fun(fmt: string, ...: any)
---@field fmt_error fun(fmt: string, ...: any)
---@field fmt_fatal fun(fmt: string, ...: any)

local Config = require("continuity.config")

---@type continuity.log
local log = require("plenary.log").new(
  ---@diagnostic disable-next-line: param-type-not-match
  vim.tbl_deep_extend("force", Config.log, { plugin = "continuity" }),
  false
)

return log

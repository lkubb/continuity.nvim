---@class continuity
local M = {}

---@namespace continuity

--- Just sets `vim.g.continuity_config`, which you can do yourself
--- without calling this function if you so desire.
--- The config is applied once any function in the `continuity` or `continuity.core`
--- modules is called, which unsets the global variable again.
--- Future writes to the global variable are recognized and result in a complete config reset,
--- meaning successive writes to the global variable do not build on top of each other.
--- If you need to force application of the passed config eagerly, pass it
--- to `continuity.config.setup` instead, which parses and applies the configuration immediately.
---@param opts? UserConfig
function M.setup(opts)
  vim.g.continuity_config = opts
end

return M

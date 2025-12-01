---@class finni
local M = {}

---@namespace finni

--- Just sets `vim.g.finni_config`, which you can do yourself
--- without calling this function if you so desire.
--- The config is applied once any function in the `finni` or `finni.core`
--- modules is called, which unsets the global variable again.
--- Future writes to the global variable are recognized and result in a complete config reset,
--- meaning successive writes to the global variable do not build on top of each other.
--- If you need to force application of the passed config eagerly, pass it
--- to `finni.config.setup` instead, which parses and applies the configuration immediately.
---@param opts? UserConfig
function M.setup(opts)
  vim.g.finni_config = opts
end

return M

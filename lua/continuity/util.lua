---@class continuity.util
---@field auto continuity.util.Auto
---@field git continuity.util.Git
---@field opts continuity.util.Opts
---@field path continuity.util.Path
local M = {}

--- Declare a require eagerly, but only load a module when it's first accessed.
---@param modname string The name of the mod whose loading should be deferred
---@return unknown
function M.lazy_require(modname)
  local mt = {}
  mt.__index = function(_, key)
    local mod = require(modname)
    mt.__index = mod
    return mod[key]
  end

  return setmetatable({}, mt)
end

setmetatable(M, {
  __index = function(self, k)
    local mod = require("continuity.util." .. k)
    if mod then
      self[k] = mod
      return mod
    end
    error(("Call to undefined module 'continuity.util.%s': %s"):format(k))
  end,
})

return M

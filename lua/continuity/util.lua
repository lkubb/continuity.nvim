---@type continuity.config
local Config

---@class continuity.util
---@field auto continuity.util.auto
---@field git continuity.util.git
---@field opts continuity.util.opts
---@field path continuity.util.path
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

--- Called before all public functions in this module.
--- Checks whether setup has been called and applies config.
--- If it's the first invocation, also initializes hooks that publish native events.
local function do_setup()
  if not Config.log or vim.g.continuity_config then
    Config.setup()
  end
end

--- Wrap all functions exposed in a table in a lazy-init check.
---@generic T
---@param mod T
---@return T
function M.lazy_setup_wrapper(mod)
  -- This file is required by config, so we need to lazy-require it
  if not Config then
    ---@diagnostic disable-next-line: unused
    Config = require("continuity.config")
  end
  -- Make sure all the API functions trigger the lazy load
  for k, v in pairs(mod) do
    if type(v) == "function" and k ~= "setup" then
      mod[k] = function(...)
        do_setup()
        return v(...)
      end
    end
  end
  return mod
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

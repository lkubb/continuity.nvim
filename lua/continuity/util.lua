---@type continuity.config
local Config

---@class continuity.util
---@field auto continuity.util.auto
---@field git continuity.util.git
---@field opts continuity.util.opts
---@field path continuity.util.path
---@field shada continuity.util.shada
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

--- When re-raising an error in try ... finally style, we would
--- like to keep the inner part of the traceback. This function
--- attempts to add it to the error message, avoiding duplication
--- of other stacktrace entries.
function M.xpcall_handler(err)
  local msg = vim.split(
    "xpcall caught error: "
      .. err
      .. "\nProtected stack traceback:"
      .. debug.traceback("", 2):sub(18),
    "\n"
  )
  local rend = ""
  for _, line in ipairs(msg) do
    if line:find("in function 'xpcall'", nil, true) then
      return rend
    end
    rend = rend .. "\n" .. line
  end
  return rend
end

local function xpc(fun, ...)
  local params = vim.F.pack_len(...)
  return vim.F.pack_len(xpcall(function()
    -- Not completely sure xpcall can take varargs in all nvim Lua envs, hence this wrapper
    ---@diagnostic disable-next-line: return-type-mismatch
    return fun(vim.F.unpack_len(params))
  end, M.xpcall_handler))
end

local function unpack_res(res)
  table.remove(res, 1)
  res.n = res.n - 1
  return vim.F.unpack_len(res)
end

--- Execute an inner function in protected mode,
--- always call another function, only then re-raise possible errors
--- while trying to preserve as much information as possible.
---@generic Returns, Params
---@param inner fun(...: Params...): Returns...
---@param always fun()
---@param ... Params...
---@return Returns...
function M.try_finally(inner, always, ...)
  local res = xpc(inner, ...)
  always()
  if not res[1] then
    error(res[2], 2)
  end
  return unpack_res(res)
end

--- Execute an inner function in protected mode.
--- On error, call another function with the error message.
--- Return either the function's or the handler's return.
--- Note: Try to avoid non-nullable or differing return values to avoid typing issues.
---@generic Returns, Params
---@param inner fun(...: Params...): Returns...
---@param handler fun(err: string): Returns...
---@param ... Params...
---@return Returns...
function M.try_catch(inner, handler, ...)
  return M.try_catch_else(inner, handler, nil, ...)
end

--- Execute an inner function in protected mode.
--- On error, call a handler function with the error message.
--- On success, call yet another function with the result (unprotected).
--- Return either the second function's or the handler's return.
--- Note: Try to avoid non-nullable or differing return values to avoid typing issues.
---@generic Returns, Transformed, Params
---@overload fun(inner: fun(...: Params...): Returns..., err_handler: fun(err: string): Returns...): Returns...
---@overload fun(inner: fun(...: Params...): Returns..., err_handler: fun(err: string): Returns..., nil): Returns...
---@param inner fun(...: Params...): Returns...
---@param err_handler fun(err: string): Transformed...
---@param success_handler? fun(...: Returns...): Transformed...
---@param ... Params...
---@return Transformed...
function M.try_catch_else(inner, err_handler, success_handler, ...)
  local res = xpc(inner, ...)
  if not res[1] then
    return err_handler(res[2])
  end
  if not success_handler then
    return unpack_res(res)
  end
  return success_handler(unpack_res(res))
end

--- Try executing a list of funcs. Return the first non-error result, if any.
--- Note: Try to avoid non-nullable or differing return values to avoid typing issues.
---@generic Returns, Params
---@param funs (fun(...: Params...): Returns...)[]
---@param ... Params...
---@return Returns...
function M.try_any(funs, ...)
  for _, fun in funs do
    local res = xpc(fun, ...)
    if res[1] then
      return unpack_res(res)
    end
  end
end

---@class TryLog.Params
---@field level? "trace"|"debug"|"info"|"warn"|"error" The level to log at. Defaults to `error`.

---@alias TryLog.Format [string, any...] A format string and variable arguments to pass to the formatter. The format string should include a final extra `%s` for the error message.
---@alias TryLog TryLog.Format & TryLog.Params The config table passed to `try_log*` functions. List of formatter args, optional key/value config.
---
--- Try to execute a function. If it fails, log a custom description and the message.
--- Otherwise return the result.
--- Note: Avoid non-nullable returns.
---@generic Returns, Params, Transformed
---@param inner fun(...: Params...): Returns...
---@param msg  TryLog
---@param success? fun(...: Returns...): Transformed...
---@param ... Params...
---@return Returns...
function M.try_log_else(inner, msg, success, ...)
  msg = msg or {}
  return M.try_catch_else(inner, function(err)
    local log = require("continuity.log")
    local fun = "fmt_" .. (msg.level or "error")
    msg[#msg + 1] = err
    log[fun](unpack(msg))
    return nil
  end, success, ...)
end

--- Try to execute a function. If it fails, log a custom description and the message.
--- Otherwise return the result.
--- Note: Avoid non-nullable returns.
---@generic Returns, Params
---@param inner fun(...: Params...): Returns...
---@param msg  TryLog
---@param ... Params...
---@return Returns...
function M.try_log(inner, msg, ...)
  return M.try_log_else(inner, msg, nil, ...)
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

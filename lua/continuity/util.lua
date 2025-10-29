---@type continuity.config
local Config

---@class continuity.util
---@field auto continuity.util.auto
---@field git continuity.util.git
---@field opts continuity.util.opts
---@field path continuity.util.path
---@field shada continuity.util.shada
local M = {}

---@namespace continuity.util

--- Declare a require eagerly, but only load a module when it's first accessed.
---@param modname string Name of the mod whose loading should be deferred
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

--- Call a function with `xpcall` and use custom handler to keep stacktrace info.
--- Ensures arguments can be passed to the function (unsure if necessary,
--- plain Lua 5.1 xpcall does not have varargs, but LuaJIT does afaict).
---@generic T
---@param fun fun(...): T... Function to run in protected mode
---@return [boolean, T...] & {n: integer} packed_rets #
---   Variadic returns of wrapped function packed via `vim.F.pack_len`
local function xpc(fun, ...)
  local params = vim.F.pack_len(...)
  return vim.F.pack_len(xpcall(function()
    -- Not completely sure xpcall can take varargs in all nvim Lua envs, hence this wrapper
    ---@diagnostic disable-next-line: return-type-mismatch
    return fun(vim.F.unpack_len(params))
  end, M.xpcall_handler))
end

--- Remove xpcall result from packed variable returns and unpack the actual function returns.
---@generic T
---@param res [boolean, T...] & {n: integer} #
---   Variadic returns of xpcall packed via `vim.F.pack_len`
---@return T... #
---   Variadic returns of wrapped function call only
local function unpack_res(res)
  table.remove(res --[[@as table]], 1)
  res.n = res.n - 1
  return vim.F.unpack_len(res)
end

--- Execute an inner function in protected mode,
--- always call another function, only then re-raise possible errors
--- while trying to preserve as much information as possible.
---@generic Rets, Args
---@param inner fun(...: Args...): Rets... Function to call (try)
---@param always fun() Function to always execute after call (finally)
---@param ... Args... Arguments for `inner`
---@return Rets... #
---   Variadic returns of `inner`
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
--- Note: Avoid differing return types between `inner` and `handler`
---@generic Rets, Args
---@param inner fun(...: Args...): Rets... Function to run in protected mode
---@param handler fun(err: string): Rets... Function to call when `inner` errors
---@param ... Args... Arguments for `inner`
---@return Rets... #
---   Variadic returns of either `inner` or `handler`
function M.try_catch(inner, handler, ...)
  return M.try_catch_else(inner, handler, nil, ...)
end

--- Execute an inner function in protected mode.
--- On error, call a handler function with the error message.
--- On success, call yet another function with the result (unprotected).
--- Return either the second function's (or wrapped functions, if no second function was specified)
--- or the error handler's return.
--- Note: Avoid differing return value types between `err_handler` and `success_handler`
---@generic InnerRets, Rets, Args
---@overload fun(inner: (fun(...: Args...): Rets...), err_handler: (fun(err: string): Rets...)): Rets...
---@overload fun(inner: (fun(...: Args...): Rets...), err_handler: (fun(err: string): Rets...), success_handler: nil, ...: Args...): Rets...
---@param inner fun(...: Args...): InnerRets... Function to run in protected mode
---@param err_handler fun(err: string): Rets... Function to call when `inner` errors
---@param success_handler fun(...: InnerRets...): Rets... #
---   Function to call with `inner` returns when `inner` succeeds. Optional (use `try_catch` when omitting though)
---@param ... Args... Arguments for `inner`
---@return Rets... #
---   Variadic returns of either `success_handler` (or `inner`, if no success handler was specified)
---   or `err_handler` (in error case).
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
--- Note: Try to avoid differing return values to avoid typing issues.
---       Returns are not resolved correctly by EmmyluaLS at the moment.
---@generic Rets, Args
---@param funs (fun(...: Args...): Rets...)[] List of functions to try in order
---@param ... Args... Arguments passed to each function
---@return Rets... #
---   Variadic returns of first successful call
function M.try_any(funs, ...)
  for _, fun in funs do
    local res = xpc(fun, ...)
    if res[1] then
      return unpack_res(res)
    end
  end
end

---@class TryLog.Params
---@field level? continuity.log.Level The level to log at. Defaults to `error`.
---@field notify? boolean #
---   Call `vim.notify` in addition to logging. Defaults to false.
---   Note: Also Influenced by user config, this just forces a notification regardless.

---@alias TryLog.Format [string, any...] A format string and variable arguments to pass to the formatter. The format string should include a final extra `%s` for the error message.
---@alias TryLog TryLog.Format & TryLog.Params The config table passed to `try_log*` functions. List of formatter args, optional key/value config.

---TODO: Once emmylua supports generic classes with variadics, refactor this into a try class, somewhat like this:
---   util.try(my_func):catch(err_handler):else(success_handler):finally(always_func):log({"load buffer", buf = ctx, win = winid})(my, args)
--- or:
---   util.try({"load buffer", log = true, buf = ctx, win = winid}):run(my_func):catch():else(success_handler)(my, args)

--- Try to execute a function. If it fails, log a custom description and the message.
--- Otherwise return the result.
--- Note: Avoid non-nullable returns.
---@generic InnerRets, Args, Rets
---@overload fun(inner: (fun(...: Args...): Rets...), msg: TryLog): Rets...
---@overload fun(inner: (fun(...: Args...): Rets...), msg: TryLog, success: nil, ...: Args...): Rets...
---@param inner fun(...: Args...): InnerRets... Function to run in protected mode
---@param msg  TryLog #
---   Log configuration. Log string + arguments to log function
---   (the error message is appended to these arguments for the log call).
---   Optionally `level` key for log level to log the error at. Defaults to `error`.
---@param success fun(...: InnerRets...): Rets... #
---   Function to call with `inner` returns if `inner` succeeds. Optional (use `try_log` when omitting though).
---@param ... Args... Arguments for `inner`
---@return Rets... #
---   Variadic returns of `success` (or `inner`, if no success specified),
---   or nothing in case of error
function M.try_log_else(inner, msg, success, ...)
  msg = msg or {} ---@type TryLog
  return M.try_catch_else(inner, function(err)
    local log = require("continuity.log")
    msg[#msg + 1] = err
    log[msg.level or "error"](unpack(msg))
    if msg.notify and log.notify_level > vim.log.levels[msg.level or "error"] then
      vim.notify(
        "[continuity] " .. msg[1]:format(unpack(msg, 2)),
        vim.log.levels[
          (msg.level --[[@as string]] or "error"):lower()
        ]
      )
    end
    return nil
  end, success, ...)
end

--- Try to execute a function. If it fails, log a custom description and the message.
--- Otherwise return the result.
--- Note: Avoid non-nullable returns in `inner` to avoid typing issues.
---@generic Rets, Args
---@param inner fun(...: Args...): Rets... Function to run in protected mode
---@param msg TryLog #
---   Log configuration. Log string + arguments to log function
---   (the error message is appended to these arguments for the log call).
---   Optionally `level` key for log level to log the error at. Defaults to `error`.
---@param ... Args... Arguments for `inner`
---@return Rets... #
---   Variadic returns of `inner` or nothing in case of error
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

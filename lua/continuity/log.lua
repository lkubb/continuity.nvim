local util = require("continuity.util")

---@namespace continuity.log

local levels_rev = {} ---@type table<vim.log.levels, Level>
for name, level in pairs(vim.log.levels) do
  levels_rev[level] = name
end

--- Default logging configuration, used before `continuity.config.setup()` is called.
---@type continuity.Config.log
local default_config = {
  level = "warn",
  format = "[%(level)s %(time)s] %(message)%(src_sep)s[%(source_path)s:%(source_line)s]",
  notify_level = "warn",
  notify_format = "%(message)s",
  notify_opts = { title = "Continuity" },
  time_format = "%Y-%m-%d %H:%M:%S",
}

--- Logging implementation
---@class continuity.Log: continuity.Log.config
local Log = {}

--- Get the absolute path to the log file in `log` (or `state`) stdpath
---@return string logfile #
local function get_log_file()
  return util.path.get_stdpath_filename("log", "continuity.log")
end

--- Python-style string interpolation (f"my var is {var}" => "my var is %(var)s").
---@param s string #
---   Format string. Like a regular Lua format string, but can reference
---   named variables in parentheses after the `%`.
---@param formats table<string, any?> Table of named parameters
---@return string formatted Interpolated string
local function f(s, formats)
  --- Source: http://lua-users.org/wiki/StringInterpolation
  return (
    s:gsub("%%%((%a%w*)%)([-0-9%.]*[cdeEfgGiouxXsq])", function(k, format)
      return formats[k] and ("%" .. format):format(formats[k]) or "%(" .. k .. ")" .. format
    end)
  )
end

--- Initialize default log handler and open handle on log file.
--- If log file is above 16 MiB, renames it to keep a single backup.
local function init()
  local logpath = get_log_file()
  local exists, stat = util.path.exists(logpath)
  if exists then
    if assert(stat).size > 16 * 1024 * 1024 then
      util.path.mv(logpath, logpath .. ".1", true)
    end
  else
    util.path.mkdir(vim.fs.dirname(logpath))
  end
  local logfile, err = io.open(logpath, "a+")
  if not logfile then
    vim.notify(
      f("Continuity: Failed opening log file at '%(path)s': %(err)s", { path = logpath, err = err }),
      vim.log.levels.ERROR,
      Log.notify_opts
    )
    return
  end
  Log.set_handler(function(rend)
    ---@type LineFormat
    local vars = {
      level = rend.level,
      message = rend.message,
      timestamp = rend.timestamp,
      dtime = vim.fn.strftime(Log.time_format, rend.timestamp),
      hrtime = rend.hrtime,
      src_path = rend.src_path,
      src_line = rend.src_line,
      src_sep = rend.message:find("\n") and "\n\t" or "\t\t",
    }
    local line = f(Log.format, vars)
    logfile:write(line .. "\n")
    logfile:flush()
    ---@diagnostic disable-next-line: undefined-field
    if vim.log.levels[rend.level] >= Log.notify_level then
      local notify_func = function()
        vim.notify(
          f(Log.notify_format, vars),
          ---@diagnostic disable-next-line: undefined-field
          vim.log.levels[rend.level],
          Log.notify_opts
        )
      end
      ---@diagnostic disable-next-line: unnecessary-if
      if vim.in_fast_event() then
        vim.schedule(notify_func)
      else
        notify_func()
      end
    end
  end)
end

--- Get the file and line of a function up the call stack.
---@param stacklevel integer Call stack level to subtract.
---@return string src_path Path to the file that contains the call
---@return integer src_line Line in `src_path` that contains the call
local function get_call_source(stacklevel)
  local info = debug.getinfo(stacklevel + 1, "Sl")
  return info.source:sub(2), info.currentline
end

--- Get the file path and start/end line of a function's definition
---@param func fun() Function reference to look up.
---@return string src_path Path to the file that defined the function.
---@return integer src_line_start First line of function definition in `src_path`
---@return integer src_line_end Last line of function definition in `src_path`
local function get_source(func)
  local info = debug.getinfo(func, "Sl")
  return info.source:sub(2), info.linedefined, info.lastlinedefined
end

--- Render a log message into a format that log handlers can handle.
---@param level vim.log.levels
---@param msg string
---@param ... any...
---@return Line
local function fmt(level, msg, ...)
  local timestamp = vim.uv.now()
  local hrtime = vim.uv.hrtime()
  local args = vim.F.pack_len(...)
  if args.n == 1 and type(args[1]) == "function" then
    local lazy_args = args[1]
    args = vim.F.pack_len(pcall(lazy_args))
    if not args[1] then
      ---@cast args[2] string
      local src_path, src_line = get_call_source(1)
      local lazy_src_path, lazy_src_start, lazy_src_end = get_source(lazy_args)
      return {
        level = "ERROR",
        message = f(
          (
            "Failed fetching lazy log args: %(err)s\n"
            .. "Log message: %(orig)s\n"
            .. "Lazy func defined in %(lazy_src_path)s "
            .. "(L#%(lazy_src_start)s-%(lazy_src_end)s)"
          ),
          {
            ---@diagnostic disable-next-line: undefined-field
            err = args[2],
            orig = vim.inspect(msg),
            lazy_src_path = lazy_src_path,
            lazy_src_start = lazy_src_start,
            lazy_src_end = lazy_src_end,
          }
        ),
        timestamp = timestamp,
        hrtime = hrtime,
        src_path = src_path,
        src_line = src_line,
      }
    end
    table.remove(args --[[@as table]], 1)
    args.n = args.n - 1
  end
  for i = 1, args.n do
    args[i] = vim.inspect(args[i])
  end
  local ok, rendered = pcall(string.format, msg, vim.F.unpack_len(args))
  if not ok then
    local src_path, src_line = get_call_source(1)
    local orig_src_path, orig_src_line = get_call_source(4)
    return {
      level = "ERROR",
      message = f(
        (
          "Failed formatting log line in call from %(orig_src_path)s "
          .. "(L#%(orig_src_line)s): %(err)s\n"
          .. "Log message: %(msg)s\n"
          .. "Args: %(args)s"
        ),
        {
          orig_src_path = orig_src_path,
          orig_src_line = orig_src_line,
          rendered = rendered,
          msg = vim.inspect(msg),
          args = vim.inspect(args),
        }
      ),
      timestamp = timestamp,
      hrtime = hrtime,
      src_path = src_path,
      src_line = src_line,
    }
  end
  local src_path, src_line = get_call_source(4)
  return {
    level = levels_rev[level],
    message = rendered,
    timestamp = timestamp,
    hrtime = hrtime,
    src_path = src_path,
    src_line = src_line,
  }
end

--- Override the active logging handler
---@param handler fun(rend: Line)? #
---   Function in charge of outputting log lines.
---   If unset, removes the active one and reinitializes the default one in the next log call
function Log.set_handler(handler)
  Log.handler = handler
end

--- Logging implementation
---@private
---@param level vim.log.levels
---@param msg string
---@param ... any...
function Log._log(level, msg, ...)
  if level < Log.level then
    return
  end
  if not Log.handler then
    init()
  end
  ---@cast Log.handler -?
  Log.handler(fmt(level, msg, ...))
end

---@overload fun(msg: string, lazy_args: fun(): any...)
---@overload fun(msg: string, ...: any...)
---@overload fun(msg: string)
---@param msg string Log format string
---@param ... any... Format parameters
function Log.trace(msg, ...)
  Log._log(vim.log.levels.TRACE, msg, ...)
end

---@overload fun(msg: string, lazy_args: fun(): any...)
---@overload fun(msg: string, ...: any...)
---@overload fun(msg: string)
---@param msg string Log format string
---@param ... any... Format parameters
function Log.debug(msg, ...)
  Log._log(vim.log.levels.DEBUG, msg, ...)
end

---@overload fun(msg: string, lazy_args: fun(): any...)
---@overload fun(msg: string, ...: any...)
---@overload fun(msg: string)
---@param msg string Log format string
---@param ... any... Format parameters
function Log.info(msg, ...)
  Log._log(vim.log.levels.INFO, msg, ...)
end

---@overload fun(msg: string, lazy_args: fun(): any...)
---@overload fun(msg: string, ...: any...)
---@param msg string Log format string
---@overload fun(msg: string)
---@param ... any... Format parameters
function Log.warn(msg, ...)
  Log._log(vim.log.levels.WARN, msg, ...)
end

---@overload fun(msg: string, lazy_args: fun(): any...)
---@overload fun(msg: string, ...: any...)
---@overload fun(msg: string)
---@param msg string Log format string
---@param ... any... Format parameters
function Log.error(msg, ...)
  Log._log(vim.log.levels.ERROR, msg, ...)
end

--- Apply configuration overrides.
--- Always resets handler.
---@param config? continuity.UserConfig.log
function Log.setup(config)
  local new = vim.tbl_extend("force", default_config, config or {}) ---@type continuity.Config.log
  Log.level = vim.log.levels[new.level:upper()]
  Log.format = new.format
  Log.notify_level = vim.log.levels[new.notify_level:upper()]
  Log.notify_format = new.notify_format
  Log.notify_opts = new.notify_opts
  Log.time_format = new.time_format
  Log.set_handler(new.handler)
end

-- Ensure basic logging works before custom overrides have been applied
Log.setup()

return Log

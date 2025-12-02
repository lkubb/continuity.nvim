---@meta
---@namespace finni.log

--- Log level name in uppercase, for internal references and log output
---@alias Level "TRACE"|"DEBUG"|"INFO"|"WARN"|"ERROR"|"OFF"

--- Log level name in lowercase, for user config
---@alias ConfigLevel "trace"|"debug"|"info"|"warn"|"error"|"off"

--- Applied logging configuration
---@class finni.Log.config
---@field level vim.log.levels Minimum log level to log at
---@field format string #
---   Log line format string. Note that this works like Python's f-strings.
---   Defaults to `[%(level)s %(dtime)s] %(message)s%(src_sep)s[%(src_path)s:%(src_line)s]`.
---   Available parameters:
---   * `level` Uppercase level name
---   * `message` Log message
---   * `dtime` Formatted date/time string
---   * `hrtime` Time in `[ns]` without absolute anchor
---   * `src_path` Path to the file that called the log function
---   * `src_line` Line in `src_path` that called the log function
---   * `src_sep` Whitespace between log line and source of call, 2 tabs for single line, newline + tab for multiline log messages
---@field notify_level vim.log.levels Minimum log level to use `vim.notify` for. Must be equal to or larger than `level`.
---@field notify_format string Same as `format`, but for `vim.notify` message display. Defaults to `%(message)s`.
---@field notify_opts table Options to pass to `vim.notify`. Defaults to `{ title = "Finni" }`
---@field time_format string #
---   `strftime` format string used for rendering time of call. Defaults to `%Y-%m-%d %H:%M:%S`
---@field handler? fun(line: Line) Function in charge of outputting log lines

--- Log call information passed to `handler`
---@class Line
---@field level Level Name of log level, uppercase
---@field message string Final, formatted log message
---@field timestamp integer UNIX timestamp of log message
---@field hrtime number High-resolution time of log message (`[ns]`, arbitrary anchor)
---@field src_path string Absolute path to the file the log call originated from
---@field src_line integer Line in `src_path` the log call originated from

--- Available variables for the `format` and `notify_format` strings
---@class LineFormat: Line
---@field dtime string Formatted date/time string, according to `time_format` config
---@field src_sep string Whitespace between log line and source of call, 2 tabs for single line, newline + tab for multiline log messages

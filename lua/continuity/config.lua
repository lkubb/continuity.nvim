---@class continuity.config: continuity.Config
local M = {}

---@namespace continuity

-- This is the user config, which can be a partial one.

--- User configuration for this plugin.
---@class UserConfig
---@field autosession? UserConfig.autosession #
---   Influence autosession behavior and contents
---@field extensions? table<string,any> #
---   Configuration for extensions, both Resession ones and those specific to Continuity.
---   Note: Continuity first tries to load specified extensions in `continuity.extensions`,
---   but falls back to `resession.extension` with a warning. Avoid this overhead
---   by specifying `resession_compat = true` in the extension config.
---@field load? UserConfig.load #
---   Configure session list information detail and sort order
---@field log? UserConfig.log #
---   Configure plugin logging
---@field session? UserConfig.session #
---   Influence session behavior and contents

--- Configure autosession behavior and contents
---@class UserConfig.autosession
---@field config? core.Session.InitOpts #
---   Save/load configuration for autosessions
---@field dir? string #
---   Name of the directory to store autosession projects in.
---   Interpreted relative to `$XDG_STATE_HOME/$NVIM_APPNAME`.
---@field spec? fun(cwd: string): auto.AutosessionSpec? #
---   This function implements the logic that derives the autosession spec from a path.
---   It calls `workspace`, `project_name`, `session_name`, `enabled` and `load_opts` to render it.
---   You can implement a custom logic here, but mind that the other functions have no effect then.
---@field workspace? fun(cwd: string): [string, boolean] #
---   Receive the effective nvim cwd, return workspace root and whether it's a git-tracked dir
---@field project_name? fun(workspace: string, git_info: auto.AutosessionSpec.GitInfo?): string #
---   Receive the workspace root dir and whether it's git-tracked and returns the project-specific session directory name.
---@field session_name? fun(meta: {cwd: string, workspace: string, project_name: string, git_info: auto.AutosessionSpec.GitInfo?}): string #
---   Receive the effective nvim cwd, the workspace root, the project name and cwd git info and generate a session name.
---@field enabled? fun(meta: {cwd: string, workspace: string, project_name: string, session_name: string}): boolean #
---   Receive the effective nvim cwd, the workspace root and project name and decide
---   whether a session should be started automatically.
---@field load_opts? fun(meta: {cwd: string, workspace: string, project_name: string, session_name: string}): auto.LoadOpts? #
---   Influence how an autosession is loaded/persisted, e.g. load the session without attaching it or disable modified persistence.

--- Configure session list information detail and sort order
---@class UserConfig.load
---@field detail? boolean #
---   Show more detail about the sessions when selecting one to load.
---   Disable if it causes lag.
---@field order? "modification_time"|"creation_time"|"filename" #
---   Session list order

--- Configure plugin logging
---@class UserConfig.log
---@field level? continuity.log.ConfigLevel Minimum level to log at. Defaults to `warn`.
---@field notify_level? continuity.log.ConfigLevel Minimum level to use `vim.notify` for. Defaults to `warn`.
---@field notify_opts? table Options to pass to `vim.notify`. Defaults to `{ title = "Continuity" }`
---@field format? string #
---   Log line format string. Note that this works like Python's f-strings.
---   Defaults to `[%(level)s %(time)s] %(message)%(src_sep)s[%(source_path)s:%(source_line)s]`.
---   Available parameters:
---   * `level` Uppercase level name
---   * `dtime` Formatted date/time string
---   * `hrtime` Time in `[ns]` without absolute anchor
---   * `message` Log message
---   * `src_sep` Whitespace between log line and source of call, 2 tabs for single line, newline + tab for multiline log messages
---   * `src_path` Path to the file that called the log function
---   * `src_line` Line in `src_path` that called the log function
---@field notify_format? string Same as `format`, but for `vim.notify` message display. Defaults to `%(message)s`.
---@field time_format? string #
---   `strftime` format string used for rendering time of call. Defaults to `%Y-%m-%d %H:%M:%S`
---@field handler? fun(line: continuity.log.Line) Custom function in charge of outputting log lines. Mostly useful in tests.

--- Configure default session behavior and contents, affects both manual and autosessions.
---@class UserConfig.session: core.Session.InitOpts
---@field dir? string #
---   Name of the directory to store regular sessions in.
---   Interpreted relative to `$XDG_STATE_HOME/$NVIM_APPNAME`.

-- Until https://github.com/EmmyLuaLs/emmylua-analyzer-rust/issues/328 is resolved:
-- NOTE: Keep in sync with above

---@class Config
---@field autosession Config.autosession Influence autosession behavior
---@field extensions table<string,any> Configuration for extensions
---@field load Config.load Configure load list contents
---@field log Config.log Logging configuration
---@field session Config.session Influence session behavior and contents

---@class Config.autosession
---@field config core.Session.InitOpts
---@field dir string
---@field spec fun(cwd: string): auto.AutosessionSpec?
---@field workspace fun(cwd: string): string, boolean
---@field project_name fun(workspace: string, git_info: auto.AutosessionSpec.GitInfo?): string
---@field session_name fun(meta: {cwd: string, workspace: string, project_name: string, git_info: auto.AutosessionSpec.GitInfo?}): string
---@field enabled fun(meta: {cwd: string, workspace: string, project_name: string, session_name: string, git_info: auto.AutosessionSpec.GitInfo?}): boolean
---@field load_opts fun(meta: {cwd: string, workspace: string, project_name: string, session_name: string, git_info: auto.AutosessionSpec.GitInfo?}): auto.LoadOpts?

---@class Config.load
---@field detail boolean
---@field order "modification_time"|"creation_time"|"filename"

---@class Config.log: UserConfig.log
---@field level continuity.log.ConfigLevel
---@field format string
---@field notify_level continuity.log.ConfigLevel
---@field notify_format string
---@field notify_opts table
---@field time_format string
---@field handler? fun(line: continuity.log.Line)

---@class Config.session
---@field dir string
---@field options string[]
---@field buf_filter fun(bufnr: integer, opts: core.snapshot.CreateOpts): boolean
---@field tab_buf_filter fun(tabpage: integer, bufnr: integer, opts: core.snapshot.CreateOpts): boolean
---@field modified boolean|"auto"
---@field autosave_enabled boolean
---@field autosave_interval integer
---@field autosave_notify boolean
---@field on_attach? core.Session.AttachHook
---@field on_detach? core.Session.DetachHook
---@field changelist boolean|"auto"
---@field jumps boolean|"auto"
---@field local_marks boolean|"auto"
---@field global_marks boolean|"auto"
---@field command_history boolean|"auto"
---@field search_history boolean|"auto"
---@field input_history boolean|"auto"
---@field expr_history boolean|"auto"
---@field debug_history boolean|"auto"

local util = require("continuity.util")

--- The default `config.session.buf_filter`. It allows the following buffers to be included in the session:
--- * all `help` buffers
--- * all **listed** buffers that correspond to a file (regular and `acwrite` type buffers with a name)
--- * when saving buffer modifications with `modified`, also **listed** unnamed buffers
---@param bufnr integer Buffer number of the buffer to check
---@param opts core.snapshot.CreateOpts
---@return boolean include_in_snapshot #
local function default_buf_filter(bufnr, opts)
  local buftype = vim.bo[bufnr].buftype
  if buftype == "help" then
    return true
  end
  if buftype ~= "" and buftype ~= "acwrite" then
    return false
  end
  -- By default, allow unnamed buffers to be persisted when buffer modifications are saved in the session.
  if opts.modified ~= true and vim.api.nvim_buf_get_name(bufnr) == "" then
    return false
  end
  return vim.bo[bufnr].buflisted
end

--- Derives autosession spec for a specific directory.
--- Returns nil when autosessions are disabled for this directory.
---@param cwd string Working directory the autosession should be rendered for.
---@return auto.AutosessionSpec? session
local function render_autosession_context(cwd)
  local workspace, is_git = M.autosession.workspace(cwd)
  -- normalize workspace dir, ensure trailing /
  workspace = util.path.norm(workspace)
  local git_info
  if is_git then
    git_info = util.git.git_info({ cwd = workspace })
  end
  local project_name = M.autosession.project_name(workspace, git_info)
  local session_name = M.autosession.session_name({
    cwd = cwd,
    git_info = git_info,
    project_name = project_name,
    workspace = workspace,
  })
  if
    not M.autosession.enabled({
      cwd = cwd,
      git_info = git_info,
      project_name = project_name,
      session_name = session_name,
      workspace = workspace,
    })
  then
    return nil
  end
  ---@type continuity.auto.AutosessionSpec
  local ret = {
    config = M.autosession.load_opts({
      cwd = cwd,
      git_info = git_info,
      project_name = project_name,
      session_name = session_name,
      workspace = workspace,
    }) or {},
    name = session_name,
    root = workspace,
    project = {
      name = project_name,
      data_dir = util.path.join(
        util.path.get_session_dir(M.autosession.dir),
        util.path.escape(project_name)
      ),
      repo = git_info,
    },
  }
  return ret
end

---@type Config
local defaults = {
  autosession = {
    config = {
      modified = false,
    },
    dir = "continuity",
    spec = render_autosession_context,
    workspace = util.git.find_workspace_root,
    project_name = util.auto.workspace_project_map,
    session_name = util.auto.generate_name,
    ---@diagnostic disable-next-line: unused
    enabled = function(meta)
      return true
    end,
    ---@diagnostic disable-next-line: unused
    load_opts = function(meta)
      return {}
    end,
  },
  extensions = {
    quickfix = {},
  },
  load = {
    detail = true,
    order = "modification_time",
  },
  log = {
    level = "warn",
    format = "[%(level)s %(time)s] %(message)%(src_sep)s[%(source_path)s:%(source_line)s]",
    notify_level = "warn",
    notify_format = "%(message)s",
    notify_opts = { title = "Continuity" },
    time_format = "%Y-%m-%d %H:%M:%S",
  },
  session = {
    dir = "session",
    options = {
      "binary",
      "bufhidden",
      "buflisted",
      "cmdheight",
      "diff",
      "filetype",
      "modifiable",
      "previewwindow",
      "readonly",
      "scrollbind",
      "winfixheight",
      "winfixwidth",
    },
    buf_filter = default_buf_filter,
    ---@diagnostic disable-next-line: unused
    tab_buf_filter = function(tabpage, bufnr, opts)
      return true
    end,
    modified = "auto",
    autosave_enabled = false,
    autosave_interval = 60,
    autosave_notify = true,
    command_history = "auto",
    search_history = "auto",
    input_history = "auto",
    expr_history = "auto",
    debug_history = "auto",
    jumps = "auto",
    changelist = "auto",
    global_marks = "auto",
    local_marks = "auto",
  },
}

--- Read configuration overrides from `vim.g.continuity_config` and
--- (re)initialize all modules that need initialization.
---@param config? UserConfig #
---   Default config overrides. This table is merged on top of `vim.g.continuity_config`,
---   which is itself merged on top of the default config.
function M.setup(config)
  ---@diagnostic disable-next-line: param-type-not-match
  local new = vim.tbl_deep_extend("force", defaults, vim.g.continuity_config or {}, config or {})

  for k, v in pairs(new) do
    M[k] = v
  end

  vim.g.continuity_config = nil

  require("continuity.log").setup(new.log)
  require("continuity.core.session").setup()
  require("continuity.core.ext").setup()
end

return M

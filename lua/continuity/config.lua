---This is the user config, which can be a partial one.
---@class continuity.UserConfig
---@field autosession? continuity.UserConfig.autosession Influence autosession behavior
---@field extensions? table<string,any> Configuration for extensions
---@field load? continuity.UserConfig.load Configure load list contents
---@field log? continuity.UserConfig.log Configuration for plenary.log
---@field session? continuity.UserConfig.session Influence session behavior and contents

---@class continuity.UserConfig.autosession
---@field config? continuity.SessionOpts Save/load configuration for autosessions
---@field dir? string The name of the directory to store autosessions in
---@field workspace? fun(cwd: string): [string, boolean] A function that receives the effective nvim cwd and returns the workspace root dir and whether it's a git-tracked dir
---@field project_name? fun(workspace: string, git_info: continuity.GitInfo?): string A function that receives the workspace root dir and whether it's git-tracked and returns the project-specific session directory name.
---@field session_name? fun(meta: {cwd: string, workspace: string, project_name: string, git_info: continuity.GitInfo?}): string A function that receives the effective nvim cwd, the workspace root, the project name and cwd git info and generates a session name.
---@field enabled? fun(meta: {cwd: string, workspace: string, project_name: string, session_name: string}): boolean A function that receives the effective nvim cwd, the workspace root and project name and decides whether a session should be started automatically.
---@field load_opts? fun(meta: {cwd: string, workspace: string, project_name: string, session_name: string}): continuity.LoadOpts? A function that can influence how an autosession is loaded/persisted, e.g. load the session without attaching it or disabling modified persistence.

---@class continuity.UserConfig.load
---@field detail? boolean Show more detail about the sessions when selecting one to load. Disable if it causes lag.
---@field order? "modification_time"|"creation_time"|"filename" Session list order

---@class continuity.UserConfig.log
---@field level? "trace"|"debug"|"info"|"warn"|"error"|"fatal" The minimum level to log for
---@field use_console? "async"|"sync"|false Print logs to neovim console. Defaults to async.
---@field use_file? boolean Print logs to logfile. Defaults to true.

---@class continuity.UserConfig.session: continuity.SessionOpts
---@field dir? string The name of the directory to store regular sessions in

-- Until https://github.com/EmmyLuaLs/emmylua-analyzer-rust/issues/328 is resolved:
-- NOTE: Keep in sync with above

---@class continuity.Config
---@field autosession continuity.Config.autosession Influence autosession behavior
---@field extensions table<string,any> Configuration for extensions
---@field load continuity.Config.load Configure load list contents
---@field log continuity.Config.log Configuration for plenary.log
---@field session continuity.Config.session Influence session behavior and contents

---@class continuity.Config.autosession
---@field config continuity.SessionOpts
---@field dir string
---@field workspace fun(cwd: string): string, boolean
---@field project_name fun(workspace: string, git_info: continuity.GitInfo?): string
---@field session_name fun(meta: {cwd: string, workspace: string, project_name: string, git_info: continuity.GitInfo?}): string
---@field enabled fun(meta: {cwd: string, workspace: string, project_name: string, session_name: string, git_info: continuity.GitInfo?}): boolean
---@field load_opts fun(meta: {cwd: string, workspace: string, project_name: string, session_name: string, git_info: continuity.GitInfo?}): continuity.LoadOpts?

---@class continuity.Config.load
---@field detail boolean
---@field order "modification_time"|"creation_time"|"filename"

---@class continuity.Config.log
---@field level "trace"|"debug"|"info"|"warn"|"error"|"fatal"
---@field use_console "async"|"sync"|false
---@field use_file boolean

---@class continuity.Config.session
---@field dir string
---@field options string[]
---@field buf_filter fun(bufnr: integer, opts: continuity.SnapshotOpts): boolean
---@field tab_buf_filter fun(tabpage: integer, bufnr: integer, opts: continuity.SnapshotOpts): boolean
---@field modified boolean|"auto"
---@field autosave_enabled boolean
---@field autosave_interval integer
---@field autosave_notify boolean
---@field on_attach? continuity.AttachHook
---@field on_detach? continuity.DetachHook

local util = require("continuity.util")

---@class continuity.config: continuity.Config
local M = {}

--- The default `config.session.buf_filter`. It allows the following buffers to be included in the session:
--- * all `help` buffers
--- * all **listed** buffers that correspond to a file (regular and `acwrite` type buffers with a name)
--- * when saving buffer modifications with `modified`, also **listed** unnamed buffers
---@param bufnr integer
---@param opts continuity.SnapshotOpts
---@return boolean
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

---@type continuity.Config
local defaults = {
  autosession = {
    config = {
      modified = false,
    },
    dir = "continuity",
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
    use_console = "async",
    use_file = true,
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
  },
}

--- Read configuration overrides from `vim.g.continuity_config` and
--- (re)initialize all modules that need initialization.
---@param config continuity.UserConfig? Default config overrides. This table is merged on top of `vim.g.continuity_config`, which is itself merged on top of the default config.
function M.setup(config)
  ---@diagnostic disable-next-line: param-type-not-match
  local new = vim.tbl_deep_extend("force", defaults, vim.g.continuity_config or {}, config or {})

  for k, v in pairs(new) do
    M[k] = v
  end

  vim.g.continuity_config = nil

  -- TODO: This should be session-specific config
  require("continuity.core").setup()
  require("continuity.core.ext").setup()
end

return M

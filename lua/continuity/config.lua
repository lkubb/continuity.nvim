---@class continuity.config: continuity.Config
local M = {}

---@namespace continuity

-- This is the user config, which can be a partial one.

--- User configuration for this plugin.
---@class UserConfig
---@field autosession? UserConfig.autosession Influence autosession behavior and contents
---@field extensions? table<string,any> Configuration for extensions, both Resession ones and those specific to Continuity. Note: Continuity first tries to load specified extensions in `continuity.extensions`, but falls back to `resession.extension` with a warning. Avoid this overhead by specifying `resession_compat = true` in the extension config.
---@field load? UserConfig.load Configure session list information detail and sort order
---@field log? UserConfig.log Configure plugin logging
---@field session? UserConfig.session Influence session behavior and contents

--- Configure autosession behavior and contents
---@class UserConfig.autosession
---@field config? core.Session.InitOpts Save/load configuration for autosessions
---@field dir? string The name of the directory to store autosessions in
---@field spec fun(cwd: string): auto.AutosessionConfig? This function implements the logic that goes from path to autosession spec. It calls `workspace`, `project_name`, `session_name`, `enabled` and `load_opts` to render it. You can implement a custom logic here, but mind that the other functions have no effect then.
---@field workspace? fun(cwd: string): [string, boolean] A function that receives the effective nvim cwd and returns the workspace root dir and whether it's a git-tracked dir
---@field project_name? fun(workspace: string, git_info: auto.AutosessionSpec.GitInfo?): string A function that receives the workspace root dir and whether it's git-tracked and returns the project-specific session directory name.
---@field session_name? fun(meta: {cwd: string, workspace: string, project_name: string, git_info: auto.AutosessionSpec.GitInfo?}): string A function that receives the effective nvim cwd, the workspace root, the project name and cwd git info and generates a session name.
---@field enabled? fun(meta: {cwd: string, workspace: string, project_name: string, session_name: string}): boolean A function that receives the effective nvim cwd, the workspace root and project name and decides whether a session should be started automatically.
---@field load_opts? fun(meta: {cwd: string, workspace: string, project_name: string, session_name: string}): auto.LoadOpts? A function that can influence how an autosession is loaded/persisted, e.g. load the session without attaching it or disabling modified persistence.

--- Configure session list information detail and sort order
---@class UserConfig.load
---@field detail? boolean Show more detail about the sessions when selecting one to load. Disable if it causes lag.
---@field order? "modification_time"|"creation_time"|"filename" Session list order

--- Configure plugin logging
---@class UserConfig.log
---@field level? "trace"|"debug"|"info"|"warn"|"error"|"fatal" The minimum level to log for
---@field use_console? "async"|"sync"|false Print logs to neovim console. Defaults to async.
---@field use_file? boolean Print logs to logfile. Defaults to true.

--- Configure default session behavior and contents, affects both manual and autosessions.
---@class UserConfig.session: core.Session.InitOpts
---@field dir? string The name of the directory to store regular sessions in

-- Until https://github.com/EmmyLuaLs/emmylua-analyzer-rust/issues/328 is resolved:
-- NOTE: Keep in sync with above

---@class Config
---@field autosession Config.autosession Influence autosession behavior
---@field extensions table<string,any> Configuration for extensions
---@field load Config.load Configure load list contents
---@field log Config.log Configuration for plenary.log
---@field session Config.session Influence session behavior and contents

---@class Config.autosession
---@field config core.Session.InitOpts
---@field dir string
---@field spec fun(cwd: string): auto.AutosessionConfig?
---@field workspace fun(cwd: string): string, boolean
---@field project_name fun(workspace: string, git_info: auto.AutosessionSpec.GitInfo?): string
---@field session_name fun(meta: {cwd: string, workspace: string, project_name: string, git_info: auto.AutosessionSpec.GitInfo?}): string
---@field enabled fun(meta: {cwd: string, workspace: string, project_name: string, session_name: string, git_info: auto.AutosessionSpec.GitInfo?}): boolean
---@field load_opts fun(meta: {cwd: string, workspace: string, project_name: string, session_name: string, git_info: auto.AutosessionSpec.GitInfo?}): auto.LoadOpts?

---@class Config.load
---@field detail boolean
---@field order "modification_time"|"creation_time"|"filename"

---@class Config.log
---@field level "trace"|"debug"|"info"|"warn"|"error"|"fatal"
---@field use_console "async"|"sync"|false
---@field use_file boolean

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

local util = require("continuity.util")

--- The default `config.session.buf_filter`. It allows the following buffers to be included in the session:
--- * all `help` buffers
--- * all **listed** buffers that correspond to a file (regular and `acwrite` type buffers with a name)
--- * when saving buffer modifications with `modified`, also **listed** unnamed buffers
---@param bufnr integer
---@param opts core.snapshot.CreateOpts
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

---Renders autosession metadata for a specific directory.
---Returns nil when autosessions are disabled for this directory.
---@param cwd string The working directory the autosession should be rendered for.
---@return auto.AutosessionConfig?
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
  local project_dir = util.auto.hash(project_name)
  ---@type continuity.auto.AutosessionSpec
  local ret = {
    cwd = cwd,
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
      data_dir = util.path.join(M.autosession.dir, project_dir),
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
---@param config? UserConfig Default config overrides. This table is merged on top of `vim.g.continuity_config`, which is itself merged on top of the default config.
function M.setup(config)
  ---@diagnostic disable-next-line: param-type-not-match
  local new = vim.tbl_deep_extend("force", defaults, vim.g.continuity_config or {}, config or {})

  for k, v in pairs(new) do
    M[k] = v
  end

  vim.g.continuity_config = nil

  require("continuity.session").setup()
  require("continuity.core.ext").setup()
end

return M

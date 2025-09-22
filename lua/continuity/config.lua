---This is the user config, which can be a partial one.
---@class continuity.UserConfig
---@field autosave? continuity.UserConfig.autosave Influence autosave behavior
---@field autosession? continuity.UserConfig.autosession Influence autosession behavior
---@field extensions? table<string,any> Configuration for extensions
---@field load? continuity.UserConfig.load Configure load list contents
---@field log? continuity.UserConfig.log Configuration for plenary.log
---@field session? continuity.UserConfig.session Influence session behavior and contents

---@class continuity.UserConfig.autosave
---@field enabled? boolean When a session is active, automatically save it in intervals. Defaults to false.
---@field interval? integer Seconds between autosaves
---@field notify? boolean Trigger a notification when autosaving. Defaults to true.

---@class continuity.UserConfig.autosession
---@field dir string? The name of the directory to store autosessions in
---@field workspace? fun(cwd: string): [string, boolean] A function that receives the effective nvim cwd and returns the workspace root dir and whether it's a git-tracked dir
---@field project_name? fun(workspace: string, git_info: continuity.GitInfo?): string A function that receives the workspace root dir and whether it's git-tracked and returns the project-specific session directory name.
---@field session_name? fun(meta: {cwd: string, workspace: string, project_name: string, git_info: continuity.GitInfo?}): string A function that receives the effective nvim cwd, the workspace root, the project name and cwd git info and generates a session name.
---@field enabled? fun(meta: {cwd: string, workspace: string, project_name: string, session_name: string}): boolean A function that receives the effective nvim cwd, the workspace root and project name and decides whether a session should be started automatically.

---@class continuity.UserConfig.load
---@field detail? boolean Show more detail about the sessions when selecting one to load. Disable if it causes lag.
---@field order? "modification_time"|"creation_time"|"filename" Session list order

---@class continuity.UserConfig.log
---@field level? "trace"|"debug"|"info"|"warn"|"error"|"fatal" The minimum level to log for
---@field use_console? "async"|"sync"|false Print logs to neovim console. Defaults to async.
---@field use_file? boolean Print logs to logfile. Defaults to true.

---@class continuity.UserConfig.session
---@field dir? string The name of the directory to store regular sessions in
---@field options? string[] Save and restore these options
---@field buf_filter? fun(integer): boolean Custom logic for determining if the buffer should be included
---@field tab_buf_filter? fun(tabpage: integer, bufnr: integer): boolean Custom logic for determining if a buffer should be included in a tab-scoped session

-- Until https://github.com/EmmyLuaLs/emmylua-analyzer-rust/issues/328 is resolved:
-- NOTE: Keep in sync with above

---@class continuity.Config
---@field autosave continuity.Config.autosave Influence autosave behavior
---@field autosession continuity.Config.autosession Influence autosession behavior
---@field extensions table<string,any> Configuration for extensions
---@field load continuity.Config.load Configure load list contents
---@field log continuity.Config.log Configuration for plenary.log
---@field session continuity.Config.session Influence session behavior and contents

---@class continuity.Config.autosave
---@field enabled boolean
---@field interval integer
---@field notify boolean

---@class continuity.Config.autosession
---@field dir string
---@field workspace fun(cwd: string): string, boolean
---@field project_name fun(workspace: string, git_info: continuity.GitInfo?): string
---@field session_name fun(meta: {cwd: string, workspace: string, project_name: string, git_info: continuity.GitInfo?}): string
---@field enabled fun(meta: {cwd: string, workspace: string, project_name: string, session_name: string}): boolean

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
---@field buf_filter fun(integer): boolean
---@field tab_buf_filter fun(tabpage: integer, bufnr: integer): boolean

local util = require("continuity.util")

---@class continuity.config: continuity.Config
---@field _pending continuity.UserConfig?
local M = {}

--- The default config.session.buf_filter (takes all buflisted files with "", "acwrite", or "help" buftype)
---@param bufnr integer
---@return boolean
local function default_buf_filter(bufnr)
  local buftype = vim.bo[bufnr].buftype
  if buftype == "help" then
    return true
  end
  if buftype ~= "" and buftype ~= "acwrite" then
    return false
  end
  if vim.api.nvim_buf_get_name(bufnr) == "" then
    return false
  end
  return vim.bo[bufnr].buflisted
end

---@type continuity.Config
local defaults = {
  autosession = {
    dir = "continuity",
    workspace = util.git.find_workspace_root,
    project_name = util.auto.workspace_project_map,
    session_name = util.auto.generate_name,
    enabled = function()
      return true
    end,
  },
  autosave = {
    enabled = false,
    interval = 60,
    notify = true,
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
    tab_buf_filter = function(tabpage, bufnr)
      return true
    end,
  },
}

---@param config continuity.UserConfig?
function M.setup(config)
  ---@diagnostic disable-next-line: param-type-not-match
  local new = vim.tbl_deep_extend("force", defaults, M._pending or {}, config or {})

  for k, v in pairs(new) do
    M[k] = v
  end

  M._pending = nil

  -- TODO: This should be session-specific config
  require("continuity.core").autosave(M.autosave.enabled, M.autosave.interval, M.autosave.notify)
  require("continuity.core.ext").setup()
end

return M

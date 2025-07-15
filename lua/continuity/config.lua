local util = require("continuity.util")

---@class continuity.log
---@field trace fun(...: any)
---@field debug fun(...: any)
---@field info fun(...: any)
---@field warn fun(...: any)
---@field error fun(...: any)
---@field fatal fun(...: any)
---@field fmt_trace fun(fmt: string, ...: any)
---@field fmt_debug fun(fmt: string, ...: any)
---@field fmt_info fun(fmt: string, ...: any)
---@field fmt_warn fun(fmt: string, ...: any)
---@field fmt_error fun(fmt: string, ...: any)
---@field fmt_fatal fun(fmt: string, ...: any)

---@class continuity.config
---@field opts continuity.Config
---@field log continuity.log
local M = {}

---This is the user config, which can be a partial one.
---@class continuity.UserConfig
---@field dir string? The directory continuity per-project autosessions are saved to
---@field workspace? fun(cwd: string): [string, boolean] A function that receives the effective nvim cwd and returns the workspace root dir and whether it's a git-tracked dir
---@field project_name? fun(workspace: string, git_info: continuity.GitInfo?): string A function that receives the workspace root dir and whether it's git-tracked and returns the project-specific session directory name.
---@field session_name? fun(meta: {cwd: string, workspace: string, project_name: string, git_info: continuity.GitInfo?}): string A function that receives the effective nvim cwd, the workspace root, the project name and cwd git info and generates a session name.
---@field enabled? fun(meta: {cwd: string, workspace: string, project_name: string, session_name: string}): boolean A function that receives the effective nvim cwd, the workspace root and project name and decides whether a session should be started automatically.
---@field log? table<string, any> Logging configuration for plenary.log

-- NOTE: Keep in sync with above

---Plugin configuration with applied defaults.
---@class continuity.Config: continuity.UserConfig
---@field dir string The directory continuity per-project autosessions are saved to
---@field workspace fun(cwd: string): (string, boolean) A function that receives the effective nvim cwd and returns the workspace root dir and whether it's a git-tracked dir
---@field project_name fun(workspace: string, git_info?: continuity.GitInfo?): string A function that receives the workspace root dir and, if git-tracked, git metadata and returns the name of the project the workspace belongs to.
---@field session_name fun(meta: {cwd: string, workspace: string, project_name: string, git_info: continuity.GitInfo?}): string A function that receives the effective nvim cwd, the workspace root, the project name and cwd git info and generates a session name.
---@field enabled fun(meta: {cwd: string, git_info?: continuity.GitInfo, workspace: string, project_name: string, session_name: string}): boolean A function that receives the effective nvim cwd, the workspace root and project name and decides whether a session should be started automatically.
---@field log table<string, any> Logging configuration for plenary.log

---@type continuity.Config
local defaults = {
  dir = "continuity",
  workspace = util.find_workspace_root,
  project_name = util.workspace_project_map,
  session_name = util.generate_name,
  enabled = function()
    return true
  end,
  log = {
    level = "warn",
    use_console = "async",
    use_file = true,
  },
}

---@param opts continuity.UserConfig?
function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", defaults, opts or {})
  ---@diagnostic disable-next-line: assign-type-mismatch
  M.log = require("plenary.log").new(
    vim.tbl_deep_extend("force", { plugin = "continuity" }, M.opts.log),
    false
  )
end

return M

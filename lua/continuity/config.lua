local util = require("continuity.util")

local M = {}

-- This is the user config, which can be a partial one. Should be kept in sync
-- with the one below.

---@class Continuity.UserConfig
---@field dir string? The directory continuity per-project autosessions are saved to
---@field workspace ( fun(cwd: string): (string, boolean) ) | nil A function that receives the effective nvim cwd and returns the workspace root dir and whether it's a git-tracked dir
---@field project_name ( fun(workspace: string, is_git: boolean): string ) | nil A function that receives the workspace root dir and whether it's git-tracked and returns the project-specific session directory name.
---@field project_encode ( fun(project_name: string): string ) | nil A function that receives the project name and encodes it for the filesystem
---@field session_name ( fun(cwd: string, workspace: string, project: string): string ) | nil A function that receives the effective nvim cwd, the workspace root and project name and generates a session name.
---@field enabled ( fun(cwd: string, workspace: string, project: string): boolean ) | nil A function that receives the effective nvim cwd, the workspace root and project name and decides whether a session should be started automatically.

---@class Continuity.Config
---@field dir string The directory continuity per-project autosessions are saved to
---@field workspace fun(cwd: string): (string, boolean) A function that receives the effective nvim cwd and returns the workspace root dir and whether it's a git-tracked dir
---@field project_name fun(workspace: string, is_git: boolean): string A function that receives the workspace root dir and whether it's git-tracked and returns the project-specific session directory name.
---@field project_encode fun(project_name: string): string A function that receives the project name and encodes it for the filesystem
---@field session_name fun(cwd: string, workspace: string, project: string): string A function that receives the effective nvim cwd, the workspace root and project name and generates a session name.
---@field enabled fun(cwd: string, workspace: string, project: string): boolean A function that receives the effective nvim cwd, the workspace root and project name and decides whether a session should be started automatically.
---@field log table<string, any> Logging configuration for plenary.log
local defaults = {
  dir = "continuity",
  workspace = util.find_workspace_root,
  project_name = util.workspace_project_map,
  project_encode = util.hash,
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

---@type Continuity.Config
M.opts = {}
M.log = nil

---@param opts Continuity.UserConfig?
function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", {}, defaults, opts or {})
  M.log = require("plenary.log").new(vim.tbl_deep_extend("force", { plugin = "continuity" }, M.opts.log), false)
end

return M

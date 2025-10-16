---@class continuity.util.auto
local M = {}

---@using continuity.auto

--- Check if nvim is running headless
---@return boolean is_headless #
function M.is_headless()
  return vim.tbl_contains(vim.v.argv, "--headless")
end

--- Get the working directory of the nvim process.
---@return string current_global_working_dir #
function M.cwd()
  local global_cwd = vim.fn.getcwd(-1, -1) -- get cwd of nvim process
  return vim.fn.fnamemodify(global_cwd, ":p")
end

--- Get the effective process cwd.
--- If nvim was invoked without arguments, it's the cwd of the nvim process.
--- If nvim was invoked with a single argument and it's a directory, return this directory instead.
--- Otherwise, return false. This means we shouldn't load or monitor at all.
---@return string|false effective_cwd #
function M.cwd_init()
  if os.getenv("NO_SESSION") then
    return false
  end
  -- Don't enable when commands are run at startup
  if vim.tbl_contains(vim.v.argv, "-c") then
    return false
  end
  local argv = vim.fn.argv()
  ---@cast argv -string
  if #argv == 0 then
    return M.cwd()
  end
  if #argv > 1 then
    return false
  end
  local arg_1 = argv[1]
  ---@cast arg_1 -nil
  if arg_1 == "." then
    return false
  end
  return vim.fn.isdirectory(arg_1) == 1 and vim.fn.fnamemodify(arg_1, ":p")
end

--- Map a workspace to a project. This is the default implementation, can be overridden by users.
--- By default, we name a project after its workspace directory. When git repos are involved,
--- we name it after the parent directory of its common git dir instead, which correctly resolves
--- multiple worktrees into the same project.
---@param workspace string Path of the workspace
---@param git_info? AutosessionSpec.GitInfo When the workspace is part of a git repository, git meta information
---@return string project_name #
function M.workspace_project_map(workspace, git_info)
  local project_name = workspace
  if git_info then
    project_name =
      require("continuity.util.path").norm(vim.fn.fnamemodify(git_info.commongitdir, ":h"))
  end
  project_name = vim.fn.fnamemodify(project_name, ":~")
  return project_name
end

--- Return the default session name.
--- If `root` is not inside a git repo, returns `default`.
--- If the currently checked out branch is the default one, returns `default`.
--- Otherwise, returns the branch name.
---@param meta {cwd: string, workspace: string, project_name: string, git_info: AutosessionSpec.GitInfo?} #
---   Workspace meta info
---@return string session_name #
function M.generate_name(meta)
  if
    meta.git_info
    and meta.git_info.branch
    and meta.git_info.default_branch
    and meta.git_info.branch ~= meta.git_info.default_branch
  then
    return meta.git_info.branch
  end
  return "default"
end

---Return the sha256 digest of `data`.
---@param data string Data to hash via sha256
---@return string hex_digest #
function M.hash(data)
  return vim.fn.sha256(data)
end

return M

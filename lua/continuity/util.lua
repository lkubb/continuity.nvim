local M = {}

-- Run `git` commands.
---@param cwd string The directory to run the command in.
---@param ... string The subcommand + options/params to run
local function git(cwd, ...)
  local res = vim.system({ "git", ... }, { cwd = cwd }):wait()
  if res.code > 0 then
    -- TODO: Logging, also fail completely if path is a git repo and we're here anyways
    return nil
  end
  return res
end

--- Get the effective process cwd.
--- If nvim was invoked without arguments, it's the cwd of the nvim process.
--- If nvim was invoked with a single argument and it's a directory, return this directory instead.
--- Otherwise, return nil. This means we shouldn't load at all.
---@return string?
function M.cwd()
  -- Don't enable when commands are run at startup
  if vim.tbl_contains(vim.v.argv, "-c") then
    return nil
  end
  local argv = vim.fn.argv()
  if #argv > 1 then
    return nil
  end
  if #argv == 0 then
    local global_cwd = vim.fn.getcwd(-1, -1) -- get cwd of nvim process
    return vim.fn.fnamemodify(global_cwd, ":p")
  end
  return vim.fn.isdirectory(argv[1]) == 1 and vim.fn.fnamemodify(argv[1], ":p") or nil
end

-- List all locally existing branches
---@param path string The path of the repository to retrieve the branches of
---@return string[]?
function M.list_branches(path)
  local res = git(path, "branch", "--list", "--format=%(refname:short)")
  return res and vim.split(res.stdout, "\n", { trimempty = true, plain = true }) or nil
end

-- Get the checked out branch of a git repository.
---@param path string The path of the repository to retrieve the branch of
---@return string?
function M.current_branch(path)
  local res = git(path, "branch", "--show-current")
  return res and vim.trim(res.stdout) or nil
end

-- Get the "default branch" of a git repository.
-- This is not really a git core concept.
---@param path string The path of the repository to retrieve the default branch of
---@return string?
function M.default_branch(path)
  local res = git(path, "rev-parse", "--abbrev-ref", "origin/HEAD")
  if res then
    return string.sub(vim.trim(res.stdout), 8)
  end
  local branches = M.list_branches(path) or {}
  if #branches == 1 then
    return branches[1]
  end
  if #branches == 0 then
    return nil
  end
  for _, name in ipairs({ "main", "master", "trunk" }) do
    if vim.tbl_contains(branches, name) then
      return name
    end
  end
  return nil
end

-- If `path` is part of a git repository, return the workspace root path, otherwise `path` itself
---@param path string The effective cwd of the current scope
---@return string
---@return boolean
function M.find_workspace_root(path)
  local root = vim.fs.root(path, ".git")
  if root then
    return root, true
  end
  return path, false
end

-- Find the project a workspace is part of.
-- Usually, it's the workspace root, unless git worktrees are used.
---@param workspace string The path of the workspace
---@param is_git boolean Whether the workspace is in a git-tracked repository
---@return string
function M.workspace_project_map(workspace, is_git)
  if not is_git then
    return workspace
  end
  return M.find_git_dir(workspace)
end

-- If `path` is part of a git repository, return the parent of the path that contains the gitdir.
-- This accounts for git worktrees.
---@param path string The effective cwd of the current scope
---@return string
function M.find_git_dir(path)
  local res = git(path, "rev-parse", "--absolute-git-dir")
  if not res then
    return path
  end
  local gitdir = vim.trim(res.stdout)
  return select(1, M.find_workspace_root(gitdir))
end

-- Return the sha256 digest of `data`.
-- Used as the default project name -> project dir mapping.
---@param data string The data to hash
---@return string
function M.hash(data)
  return vim.fn.sha256(data)
end

-- Return the default session name.
-- If `root` is not inside a git repo, returns `default`.
-- If the currently checked out branch is the default one, returns `default`.
-- Otherwise, returns the branch name.
---@return string
function M.generate_name(_, root, _)
  local default = "default"
  local cur_branch = M.current_branch(root)
  if not cur_branch then
    return default
  end
  local default_branch = M.default_branch(root)
  if not default_branch or default_branch == cur_branch then
    return "default"
  end
  return cur_branch
end

-- Check if nvim is running headless
---@return boolean
function M.is_headless()
  return vim.tbl_contains(vim.v.argv, "--headless")
end

function M.list_buffers()
  local res = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    table.insert(res, {
      buf = buf,
      name = vim.api.nvim_buf_get_name(buf),
      uuid = vim.b[buf].resession_uuid,
    })
  end
  return res
end

function M.list_modified_buffers()
  local res = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if
      vim.b[buf]._continuity_needs_restore
      or vim.api.nvim_get_option_value("modified", { buf = buf })
    then
      table.insert(res, {
        buf = buf,
        name = vim.api.nvim_buf_get_name(buf),
        uuid = vim.b[buf].resession_uuid,
      })
    end
  end
  return res
end

function M.list_untitled_buffers()
  local res = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf) == "" then
      table.insert(res, { buf = buf, uuid = vim.b[buf].resession_uuid })
    end
  end
  return res
end

function M.get_buf_by_name(name)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf) == name then
      return buf
    end
  end
end

function M.read_lines(file)
  local lines = {}
  for line in io.lines(file) do
    lines[#lines + 1] = line
  end
  return lines
end

return M

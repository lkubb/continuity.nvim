local M = {}

---@class Continuity.util.GitCmdOpts: vim.SystemOpts
---@field ignore_error? boolean Don't raise errors when the command fails.
---@field trim_empty_lines? boolean When splitting stdout, remove empty elements of the array. Defaults to false.
---@field gitdir? string A gitdir path to pass to Git explicitly.
---@field worktree? string A worktree path to pass to Git explicitly.

--- Wrapper for vim.system for git commands. Raises errors by default.
---@param cmd string[] The command to run
---@param opts Continuity.util.GitCmdOpts? Modifiers for vim.system and additional ignore_errors option.
---@return string[] stdout_lines
---@return string? stderr
---@return integer exitcode
local function git_cmd(cmd, opts)
  local sysopts = vim.tbl_extend("force", { text = true }, opts or {})
  local gitcmd = {
    "git",
    "--no-pager",
    "--literal-pathspecs",
    "--no-optional-locks",
    "-c",
    "gc.auto=0",
  }
  for opt, param in pairs({ gitdir = "gitdir", worktree = "work-tree" }) do
    if sysopts[opt] then
      gitcmd = vim.list_extend(gitcmd, { ("--%s"):format(param), sysopts[opt] })
    end
  end
  gitcmd = vim.list_extend(gitcmd, cmd)
  local res = vim.system(gitcmd, sysopts):wait()
  if res.code > 0 and sysopts.ignore_error ~= true then
    error(
      ("Failed running command (code: %d/signal: %d)!\nCommand: %s\nstderr: %s\nstdout: %s"):format(
        res.code,
        res.signal,
        table.concat(cmd, " "),
        res.stderr,
        res.stdout
      )
    )
  end
  local lines =
    vim.split(res.stdout or "", "\n", { plain = true, trimempty = sysopts.trim_empty_lines })
  if sysopts.text and lines[#lines] == "" then
    lines[#lines] = nil
  end
  return lines, res.stderr, res.code
end

-- Run `git` commands with varargs. Returns nil on error.
---@param cwd string The directory to run the command in.
---@param ... string The subcommand + options/params to run
---@return string[]?
local function git(cwd, ...)
  local stdout, _, code = git_cmd({ ... }, { cwd = cwd, ignore_error = true, text = true })
  if code > 0 then
    -- TODO: Logging, also fail completely if path is a git repo and we're here anyways
    return nil
  end
  return stdout
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
  return git(path, "branch", "--list", "--format=%(refname:short)")
end

-- Get the checked out branch of a git repository.
---@param path string The path of the repository to retrieve the branch of
---@return string?
function M.current_branch(path)
  local res = git(path, "branch", "--show-current")
  if res and res[1] and res[1] ~= "" then
    return res[1]
  end

  -- We might be in the process of an interactive rebase
  local gitdir = git(path, "rev-parse", "--absolute-git-dir")
  if not (gitdir and gitdir[1] and gitdir[1] ~= "") then
    return
  end
  local f = require("resession.files")
  for _, dir in ipairs({ "rebase-merge", "rebase-apply" }) do
    local head_name_path = f.join(gitdir[1], dir, "head-name")
    local short_name = f.read_file(head_name_path)
    if short_name then
      return vim.trim(short_name:gsub("^refs/heads/", ""))
    end
  end
end

---@param path? string Override CWD of the git process
---@param gitdir? string Override GIT_DIR of the git process
---@param worktree? string Override GIT_WORK_TREE of the git process
---@return {toplevel?: string, gitdir?: string, branch?: string, default_branch?: string}?
function M.git_info(path, gitdir, worktree)
  local stdout, stderr, code = git_cmd({
    "rev-parse",
    "--show-toplevel", -- 1
    "--absolute-git-dir", -- 2
    "--abbrev-ref", -- 3
    "HEAD",
    "--abbrev-ref", -- 4
    "origin/HEAD",
  }, {
    ignore_error = true,
    text = true,
    gitdir = gitdir,
    worktree = worktree,
    cwd = not worktree and path or nil,
  })
  -- ignore uninitialized repos
  if
    code > 0
    and stderr
    and (
      stderr:match("fatal: ambiguous argument 'HEAD'")
      or stderr:match("fatal: ambiguous argument 'origin/HEAD'")
    )
  then
    code = 0
  end
  if code > 0 then
    return
  end
  if #stdout < 3 then
    -- We expect at least 3 lines, the 4th one misses if the 3rd one fails (abbrev-ref HEAD)
    -- because we're in an empty repo. In this case, git just returns HEAD for the 3rd one.
    return
  end
  local toplevel = stdout[1]
  local gitdir_r = stdout[2]
  -- This is not really the branch, but HEAD.
  local branch = stdout[3]
  if branch == "HEAD" and path then
    -- No commits in this repo yet (or during rebase)
    branch = M.current_branch(path)
  end
  local default_branch = stdout[4] and vim.trim(assert(stdout[4]):sub(8))
  if not default_branch and path then
    default_branch = M.default_branch(path)
  end
  return {
    toplevel = toplevel,
    gitdir = gitdir_r,
    branch = branch,
    default_branch = default_branch,
  }
end

-- Get the "default branch" of a git repository.
-- This is not really a git core concept.
---@param path string The path of the repository to retrieve the default branch of
---@return string?
function M.default_branch(path)
  local res = git(path, "rev-parse", "--abbrev-ref", "origin/HEAD")
  if res then
    return string.sub(assert(res[1]), 8)
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
---@return string root The workspace root path or `path` itself
---@return boolean is_repo Whether `path` is in a git repo
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
  local root = M.find_workspace_root(assert(res[1]))
  return root
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
      vim.b[buf].resession_uuid -- Only list buffers that are known to resession. This funtion is called during save, a missing uuid means the buffer should not be saved at all
      and (vim.b[buf]._continuity_needs_restore or vim.bo[buf].modified)
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

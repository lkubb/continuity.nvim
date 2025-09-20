---@class continuity.util.Git
local M = {}

---@class continuity.util.GitOpts
---@field cwd? string Override the working directory of the git process
---@field gitdir? string A gitdir path to pass to Git explicitly.
---@field worktree? string A worktree path to pass to Git explicitly.

---@class continuity.util.GitCmdOpts: vim.SystemOpts, continuity.util.GitOpts
---@field ignore_error? boolean Don't raise errors when the command fails.
---@field trim_empty_lines? boolean When splitting stdout, remove empty elements of the array. Defaults to false.

---Wrapper for vim.system for git commands. Raises errors by default.
---@param cmd string[] The command to run
---@param opts continuity.util.GitCmdOpts? Modifiers for vim.system and additional ignore_errors option.
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
  for opt, param in pairs({ gitdir = "git-dir", worktree = "work-tree" }) do
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

---Run `git` commands with varargs. Returns nil on error.
---@param opts? continuity.util.GitOpts Override cwd/gitdir/worktree of the git process
---@param ... string The subcommand + options/params to run
---@return string[]?
local function git(opts, ...)
  local git_opts = opts or {} --[[@as continuity.util.GitOpts]]
  ---@type continuity.util.GitCmdOpts
  local cmd_opts = {
    ignore_error = true,
    text = true,
    gitdir = git_opts.gitdir,
    worktree = git_opts.worktree,
    cwd = git_opts.cwd,
  }
  local stdout, _, code = git_cmd({ ... }, cmd_opts)
  if code > 0 then
    -- TODO: Logging, also fail completely if path is a git repo and we're here anyways
    return nil
  end
  return stdout
end

---List all locally existing branches
---@param opts? continuity.util.GitOpts Override cwd/gitdir/worktree of the git process
---@return string[]?
function M.list_branches(opts)
  return git(opts, "branch", "--list", "--format=%(refname:short)")
end

---Get the checked out branch of a git repository.
---@param opts? continuity.util.GitOpts Override cwd/gitdir/worktree of the git process
---@return string?
function M.current_branch(opts)
  local res = git(opts, "branch", "--show-current")
  if res and res[1] and res[1] ~= "" then
    return res[1]
  end

  -- We might be in the process of an interactive rebase
  local gitdir = git(opts, "rev-parse", "--absolute-git-dir")
  if not (gitdir and gitdir[1] and gitdir[1] ~= "") then
    return
  end
  ---@cast gitdir -nil
  local path = require("continuity.util.path")
  for _, dir in ipairs({ "rebase-merge", "rebase-apply" }) do
    local head_name_path = path.join(gitdir[1], dir, "head-name")
    local short_name = path.read_file(head_name_path)
    if short_name then
      return vim.trim(short_name:gsub("^refs/heads/", ""))
    end
  end
end

---@param opts? continuity.util.GitOpts Override cwd/gitdir/worktree of the git process
---@return continuity.GitInfo?
--@return {toplevel?: string, gitdir?: string, branch?: string, default_branch?: string}?
function M.git_info(opts)
  opts = opts or {}
  local stdout, stderr, code = git_cmd({
    "rev-parse",
    "--path-format=absolute",
    "--show-toplevel", -- 1
    "--absolute-git-dir", -- 2
    "--git-common-dir", -- 3
    "--abbrev-ref", -- 4
    "HEAD",
    "--abbrev-ref", -- 5
    "origin/HEAD",
  }, {
    ignore_error = true,
    text = true,
    gitdir = opts.gitdir,
    worktree = opts.worktree,
    cwd = not opts.worktree and opts.cwd or nil,
  })
  -- ignore uninitialized repo errors
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
  if #stdout < 4 then
    -- We expect at least 4 lines, the 5th one misses if the 4th one fails (abbrev-ref HEAD)
    -- because we're in an empty repo. In this case, git just returns HEAD for the 4th one.
    return
  end
  local toplevel = assert(stdout[1])
  local gitdir_r = assert(stdout[2])
  local commongitdir = assert(stdout[3])
  -- This is not really the branch, but HEAD.
  local branch = stdout[4]
  if branch == "HEAD" then
    -- No commits in this repo yet (or during rebase)
    branch = M.current_branch({ gitdir = gitdir_r, worktree = toplevel })
  end
  local default_branch = stdout[5] and vim.trim(stdout[5]:sub(8))
  if not default_branch or default_branch == "HEAD" then
    default_branch = M.default_branch({ gitdir = gitdir_r, worktree = toplevel })
  end
  return {
    commongitdir = commongitdir,
    gitdir = gitdir_r,
    toplevel = toplevel,
    branch = branch,
    default_branch = default_branch,
  }
end

---Get the "default branch" of a git repository.
---This is not really a git core concept.
---@param opts? continuity.util.GitOpts Override cwd/gitdir/worktree of the git process
---@return string?
function M.default_branch(opts)
  local res = git(opts, "rev-parse", "--abbrev-ref", "origin/HEAD")
  if res then
    return string.sub(assert(res[1]), 8)
  end
  local branches = M.list_branches(opts) or {}
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

---If `path` is part of a git repository, return the workspace root path, otherwise `path` itself.
---Note: Does not account for git submodules. You can call git rev-parse --show-superproject-working-tree
---to resolve a submodule to its parent project in a custom implementation of this function.
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

---If `path` is part of a git repository, return the parent of the path that contains the gitdir.
---This accounts for git worktrees.
---@param path string The effective cwd of the current scope
---@return string
function M.find_git_dir(path)
  local res = git({ cwd = path }, "rev-parse", "--absolute-git-dir")
  if not res then
    return path
  end
  local root = M.find_workspace_root(assert(res[1]))
  return root
end

return M

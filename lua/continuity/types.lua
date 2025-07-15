---@meta

---@class continuity.GitInfo
---@field commongitdir string The common git dir, usually equal to gitdir, unless the worktree is not the default workdir (e.g. in worktree checkuots of bare repos). Then it's the actual repo root and gitdir is <git_common_dir>/worktrees/<worktree_name>
---@field gitdir string The repository (or worktree) data path
---@field toplevel string The path of the checked out worktree
---@field branch? string The branch the worktree has checked out
---@field default_branch? string The name of the default branch

---@class continuity.ProjectInfo
---@field data_dir string The path of the directory that is used to save autosession data related to this project
---@field name string The name of the project
---@field repo continuity.GitInfo? When the project is defined as a git repository, meta info

---@class continuity.AutosessionSpec
---@field project continuity.ProjectInfo Information about the project the session belongs to
---@field root string The top level directory for this session. Usually equals the project root, but can be different when git worktrees are used.
---@field name string The name of the session

---@class continuity.Autosession: continuity.AutosessionSpec
---@field cwd string The effective working directory that was determined when loading this auto-session

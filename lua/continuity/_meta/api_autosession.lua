---@meta
---@namespace continuity.auto
---@using continuity.core
---@using continuity.SideEffects

--- API options for `auto.load`
---@alias LoadOpts Session.InitOptsWithMeta & Attach & Save & ResetAuto & SilenceErrors & PassthroughOpts
---@alias LoadOptsParsed LoadOpts & Reset

--- API options for `auto.save`
---@alias SaveOpts Attach & Notify & Reset

--- API options for `auto.reset`
---@class ResetOpts: Notify & Reset & SilenceErrors
---@field reload? boolean Attempt to restart a new autosession after reset. Defaults to true.

---@class ActiveAutosession<T: Session.Target>: ActiveSession<T>
---@field meta {autosession: AutosessionConfig}

--- A function that is called during Neovim startup. It receives information
--- about the current process initialization context and decides whether to
--- enable autosession monitoring and if we should load an autosession during startup.
--- Needs to be set in `vim.g.continuity_autosession` before plugins are initialized.
---
--- Possible return values:
---
--- * `false` to disable monitoring.
---    Autosessions need to be enabled manually if desired.
--- * `nil` to enable automatic monitoring.
---    Don't load an autosession during startup, but still
---    monitor for directory/branch changes.
--- * the path to a directory.
---   The corresponding autosession is loaded afterwards.
---
--- The default function behaves as follows:
---
--- It disables monitoring in the following cases:
--- * If we're in headless or pager mode.
--- * If Neovim was told to open a specific file.
--- * If `argv` contains more than one argument or contains `-c` (commands to be run).
---
--- If Neovim was launched without arguments, loads the autosession for the process' CWD.
--- If the single argument passed to Neovim is a directory, loads the autosession for that directory.
--- There's no case where it enables monitoring without immediately loading an autosession.
---@alias InitHandler fun(ctx: {is_headless: boolean, is_pager: boolean}): (string|false)?

---@class AutosessionSpec
---@field project AutosessionSpec.ProjectInfo Information about the project the session belongs to
---@field root string The top level directory for this session. Usually equals the project root, but can be different when git worktrees are used.
---@field name string The name of the session
---@field config LoadOpts Session-specific load/autosave options.

---@class AutosessionSpec.ProjectInfo
---@field data_dir string The path of the directory that is used to save autosession data related to this project
---@field name string The name of the project
---@field repo GitInfo? When the project is defined as a git repository, meta info

---@class AutosessionSpec.GitInfo
---@field commongitdir string The common git dir, usually equal to gitdir, unless the worktree is not the default workdir (e.g. in worktree checkuots of bare repos). Then it's the actual repo root and gitdir is <git_common_dir>/worktrees/<worktree_name>
---@field gitdir string The repository (or worktree) data path
---@field toplevel string The path of the checked out worktree
---@field branch? string The branch the worktree has checked out
---@field default_branch? string The name of the default branch

---@class AutosessionConfig: AutosessionSpec
---@field cwd string The effective working directory that was determined when loading this auto-session

---@class ActiveAutosessionInfo: ActiveSessionInfo
---@field is_autosession boolean Whether this is an autosession or a manual one
---@field autosession_config? AutosessionConfig WHen this is an autosession, the internal configuration that was rendered.
---@field autosession_data? Snapshot The most recent snapshotted state of this named autosession

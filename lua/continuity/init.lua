-- Setup autoloading and autosaving of resession sessions per project.

-- TODO: Improve usability, a lot. I'm currently mapping project names
-- to directories by just hashing them, which hinders discoverability.
-- Session names are not escaped in any way, which means branches such
-- as fix/foobar will be rendered into a subdirectory.
-- Consider something like https://github.com/jedrzejboczar/possession.nvim/pull/55
-- or use the registry implementation as a light database.
-- Note that (neo)vim saves undo files with just the pathsep replaced by %,
-- which makes sense since they have to be valid file paths, but we cannot
-- assume project_name is equivalent to a valid path, hence we need some kind
-- of encoding.

-- TODO: Allow creating named sessions other than the default one?

-- TODO: Write tests

-- TODO: Better swapfile handling, see https://github.com/neovim/neovim/issues/5086
-- Refs:
--   https://old.reddit.com/r/neovim/comments/1hkpgar/a_per_project_shadafile/
--   https://github.com/psych3r/vim-remembers/blob/master/plugin/remembers.vim#L86
--   https://github.com/jedrzejboczar/possession.nvim
--   https://github.com/rmagatti/auto-session
--   https://github.com/folke/persistence.nvim
--   https://github.com/olimorris/persisted.nvim
--   https://github.com/Shatur/neovim-session-manager
--   https://github.com/echasnovski/mini.sessions

local Config = require("continuity.config")
local util = require("continuity.util")

local lazy_require = util.lazy_require
local Core = lazy_require("continuity.core")
local Manager = lazy_require("continuity.core.manager")
local Session = lazy_require("continuity.core.session")
local log = lazy_require("continuity.log")

-- Monitor the currently active branch and check if we need to reload when it changes
---@type string?
local last_head
-- When an autosession is active, the augroup that monitors for changes (git branch, global cwd)
-- to automatically save and reload when necessary
---@type integer?
local monitor_group

--- Return the autosession context if there is an attached session and it's an autosession.
---@return continuity.Autosession?
local function current_autosession()
  local cur = Manager.get_current_data()
  if not cur or not cur.meta or not cur.meta.autosession then
    return
  end
  return cur.meta.autosession
end

--- Merge save/load opts for passing into core funcs.
---@generic T: (continuity.SaveOpts|continuity.LoadOpts)?
---@param cur continuity.Autosession Autosession to operate on
---@param defaults? table<string, any> Call-specific defaults
---@param opts? T Opts passed to the function
---@param forced? table<string, any> Call-specific forced params
---@return T - nil
local function core_opts(cur, defaults, opts, forced)
  return vim.tbl_extend(
    "force",
    Config.autosession.config,
    defaults or {},
    cur.config,
    opts or {},
    forced or {},
    { meta = { autosession = cur }, dir = cur.project.data_dir }
  )
end

---Renders autosession metadata for a specific directory.
---Returns nil when autosessions are disabled for this directory.
---@param cwd string The working directory the autosession should be rendered for.
---@return continuity.Autosession?
local function render_autosession_context(cwd)
  local workspace, is_git = Config.autosession.workspace(cwd)
  -- normalize workspace dir, ensure trailing /
  workspace = util.path.norm(workspace)
  local git_info
  if is_git then
    git_info = util.git.git_info({ cwd = workspace })
  end
  local project_name = Config.autosession.project_name(workspace, git_info)
  local session_name = Config.autosession.session_name({
    cwd = cwd,
    git_info = git_info,
    project_name = project_name,
    workspace = workspace,
  })
  if
    not Config.autosession.enabled({
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
  return {
    cwd = cwd,
    config = Config.autosession.load_opts({
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
      data_dir = util.path.join(Config.autosession.dir, project_dir),
      repo = git_info,
    },
  }
end

---@type fun(autosession: continuity.Autosession?)
local monitor

---@class continuity
local M = {}

---Save the currently active autosession.
---@param opts? continuity.SaveOpts Parameters for continuity.core.save
function M.save(opts)
  local cur = current_autosession()
  if not cur then
    return
  end
  opts = core_opts(cur, { attach = true, notify = false }, opts)
  Core.save(cur.name, opts)
end

---Save the currently active autosession and stop autosaving it after.
---Does not close anything after detaching.
---@param opts? continuity.SaveOpts Parameters for continuity.core.save
function M.detach(opts)
  local cur = current_autosession()
  if not cur then
    return
  end
  opts = vim.tbl_extend("force", opts or {}, { attach = false })
  M.save(opts)
end

---Load an autosession.
---@param autosession (continuity.Autosession|string)? The autosession table as rendered by render_autosession_context
---@param opts continuity.LoadOpts? Parameters for continuity.core.load. silence_errors is forced to true.
function M.load(autosession, opts)
  if type(autosession) == "string" then
    autosession = render_autosession_context(autosession)
  end
  monitor(autosession)
  if not autosession then
    return
  end
  -- No need to detach, it's handled by the pre-load hook.
  local load_opts = core_opts(
    autosession,
    { attach = true, reset = true },
    opts,
    { silence_errors = false }
  )

  log.fmt_debug(
    "Loading autosession %s with opts %s.\nData: %s",
    autosession.name,
    opts,
    autosession
  )

  -- TODO: Use xpcall and error handler to show better stacktrace
  local ok, err = pcall(Core.load, autosession.name, load_opts)

  if not ok then
    ---@cast err string
    if not err:find("Could not find session", nil, true) then
      vim.notify("Error loading session: " .. err, vim.log.levels.ERROR)
      return
    end
    local save_opts =
      core_opts(autosession, { attach = true, notify = false }, opts --[[@as continuity.SaveOpts]])
    if not save_opts.attach then
      -- The autosession is used to setup a default view instead of session persistence,
      -- but the referenced session does not exist.
      vim.notify(
        "Could not find autosession '{}' in project '{}', cannot start a new one because attach was set to false. "
          .. "Make sure the session file exists if you configure autloading sessions without attaching after.",
        vim.log.levels.ERROR
      )
      return
    end
    -- The session did not exist, need to save to initialize an empty one.
    -- First, change cwd to workspace root since resession saves/restores cwd.
    vim.api.nvim_set_current_dir(autosession.root)
    Core.save(autosession.name, save_opts)
  end
end

---If an autosession is active, save it and detach. Then try to start a new one.
function M.reload()
  log.fmt_trace("Reload called. Checking if we need to reload")
  local effective_cwd = util.auto.cwd()
  local autosession = render_autosession_context(effective_cwd)
  local cur = current_autosession()
  if not autosession then
    if cur then
      log.fmt_trace("Reload check result: New context disables active autosession")
      M.detach()
      require("continuity.core.layout").close_everything()
    else
      log.fmt_trace(
        "Reload check result: No active autosession, new context is disabled as well. Nothing to do."
      )
    end
    return
  end
  if cur and cur.project.name == autosession.project.name and cur.name == autosession.name then
    log.fmt_trace(
      "Reload check result: Not reloading because new context has same project and session name as active session"
    )
    return
  end
  log.fmt_trace("Reloading. Current session:\n%s\nNew session:\n%s", cur or "nil", autosession)
  -- Don't call save here, it's done in a pre_load hook which calls detach().
  M.load(autosession)
end

---Remove all monitoring hooks.
local function stop_monitoring()
  if monitor_group then
    vim.api.nvim_clear_autocmds({ group = monitor_group })
    monitor_group = nil
  end
  last_head = nil
  -- TODO: Should we remove buffer-local variables like _continuity_needs_restore?
end

---Load the continuity extension for resession and create hooks that:
---1. When resession loads another session, try to detach/save an active autosession.
---2. When neovim exits, save an active autosession.
---3. When the session is associated with a git repo and gitsigns is available, save/detach/reload active autosession on branch changes.
---4. When the global CWD changes, save/detach/reload active autosession.
---@param autosession continuity.Autosession? The active autosession that should be monitored
function monitor(autosession)
  monitor_group = vim.api.nvim_create_augroup("ContinuityHooks", { clear = true })

  ---@type boolean?
  local gitsigns_in_sync = false
  local autosession_head = autosession
    and autosession.project.repo
    and autosession.project.repo.branch
  last_head = nil

  if not autosession then
    -- If we're not inside an autosession currently, just set it later so it's
    -- in sync with gitsigns
    gitsigns_in_sync = nil
  ---@diagnostic disable-next-line: unnecessary-if
  elseif vim.g.gitsigns_head then
    if vim.g.gitsigns_head == "" then
      log.debug("vim.g.gitsigns_head is empty string, this is likely an empty repo")
    elseif not autosession_head then
      log.debug("vim.g.gitsigns_head is set, while the loading autosession does not have a branch")
    ---@diagnostic disable-next-line: need-check-nil
    elseif vim.g.gitsigns_head ~= autosession.project.repo.branch then
      log.debug("vim.g.gitsigns_head does not match autosession branch")
    else
      last_head = vim.g.gitsigns_head
      gitsigns_in_sync = true
    end
  elseif autosession_head then
    log.debug(
      "vim.g.gitsigns_head is not set, while the loading autosession has a branch. Either gitsigns is not enabled or needs to catch up still"
    )
  else
    gitsigns_in_sync = true
  end

  local check_sync = function()
    if not gitsigns_in_sync then
      if gitsigns_in_sync == nil then
        -- We don't have an active session, just follow gitsigns' lead
        autosession_head = vim.g.gitsigns_head
      elseif autosession_head ~= vim.g.gitsigns_head then
        -- gitsigns does not assign this in 'detached' state (e.g. bare repo with worktree)
        -- and assigns an empty string when it's an empty repo.
        -- In either case, we don't want to react here. This means worktrees are not watched for branch changes.
        return
      end
      ---@diagnostic disable-next-line: unused
      gitsigns_in_sync = true
      last_head = autosession_head
      log.debug("Gitsigns branch monitoring now active")
    end
    return true
  end

  -- Integrate with GitSigns to watch current branch, but not immediately after start
  -- to avoid race conditions
  vim.defer_fn(function()
    -- If we were not in sync when starting monitoring, try again. We're skipping
    -- the events GitSigns dispatches during startup, but it doesn't send any updates
    -- until something changes, which means if the first change is a branch change,
    -- we would miss it and stay out of sync.
    if not gitsigns_in_sync and not check_sync() then
      -- If we're here, we still couldn't sync. Try one last time later.
      vim.defer_fn(check_sync, 1000)
    end
    vim.api.nvim_create_autocmd("User", {
      pattern = "GitSignsUpdate",
      callback = function()
        if not gitsigns_in_sync and not check_sync() then
          return
        end
        if last_head ~= vim.g.gitsigns_head then
          log.fmt_trace(
            "Reloading project, switched from branch %s to branch %s",
            last_head or "nil",
            vim.g.gitsigns_head or "nil"
          )
          M.reload()
        end
        ---@diagnostic disable-next-line: unused
        last_head = vim.g.gitsigns_head
      end,
      group = monitor_group,
    })
  end, 500)

  vim.api.nvim_create_autocmd("DirChangedPre", {
    pattern = "global",
    callback = function()
      log.fmt_trace(
        "DirChangedPre: Global directory is going to change, checking if we need to detach before"
      )
      local cur = current_autosession()
      if not cur or Session.is_loading() then
        -- We don't need to detach if we don't have an active session or
        -- if we're in the process of loading one
        return
      end
      ---@diagnostic disable-next-line: undefined-field
      local lookahead = render_autosession_context(vim.v.event.directory)
      if
        not lookahead
        or cur.project.name ~= lookahead.project.name
        or cur.name ~= lookahead.name
      then
        log.fmt_trace(
          "DirChangedPre: Need to detach because session is going to change. Current session:\n%s\nNew session:\n%s",
          cur,
          lookahead or "nil"
        )
        -- We're going to switch/disable the active autosession.
        -- Ensure we detach before the global cwd is changed, otherwise
        -- Resession saves the new one in the current session instead.
        M.detach()
      end
    end,
    group = monitor_group,
  })
  vim.api.nvim_create_autocmd("DirChanged", {
    pattern = "global",
    callback = function()
      if not Session.is_loading() then
        log.fmt_trace("DirChanged: trying reload")
        M.reload()
      end
    end,
    group = monitor_group,
  })
end

---Start Continuity:
---1. If the current working directory has an associated project and session, closes everything and loads that session.
---2. In any case, start monitoring for directory or branch changes.
---@param cwd string? The working directory to switch to before starting autosession. Defaults to nvim's process' cwd.
---@param opts continuity.LoadOpts? Parameters for continuity.core.load. silence_errors is forced to true.
function M.start(cwd, opts)
  M.load(cwd or util.auto.cwd(), opts)
end

---Stop Continuity:
---1. If we're inside an active autosession, save it and detach. Does not close everything by default.
---2. In any case, stop monitoring for directory or branch changes.
function M.stop()
  stop_monitoring()
  M.detach()
end

---Reset the currently active autosession. Closes everything.
---@param opts? continuity.ResetOpts Options to influence execution (TODO docs)
function M.reset(opts)
  local cur = current_autosession()
  if not cur then
    return
  end
  opts = vim.tbl_extend("force", { notify = false }, opts or {})
  opts.dir = cur.project.data_dir
  Core.detach()
  Core.delete(cur.name, { dir = cur.project.data_dir, notify = opts.notify })
  require("continuity.core.layout").close_everything()
  if opts.reload ~= false then
    M.reload()
  end
end

---Remove all autosessions associated with a project.
---If the target is the active project, resets current session as well and closes everything.
---@param opts {name?: string}? Specify the project to reset. If unspecified, resets active project, if available.
function M.reset_project(opts)
  opts = opts or {}
  local name = opts.name
  local cur = current_autosession()
  if not name then
    if not cur then
      return
    end
    name = cur.project.name
  end

  local continuity_dir = util.path.get_session_dir(Config.autosession.dir)
  local project_dir = util.path.join(continuity_dir, util.auto.hash(name))
  if not util.path.exists(project_dir) then
    return
  end

  local resetting_active = false
  -- If we're resetting the active project, ensure we detach from the active session before deleting the data
  if cur and project_dir:find(cur.project.data_dir) then
    M.reset({ reload = false })
    resetting_active = true
  end

  local expected_parent = util.path.get_stdpath_filename("data", Config.autosession.dir)
  assert(project_dir:sub(1, #expected_parent) == expected_parent) -- sanity check before recursively deleting
  util.path.rmdir(project_dir, { recursive = true })

  if resetting_active then
    M.reload()
  end
end

---List autosessions associated with a project.
---@param opts {cwd?: string}? Specify the project to list. If unspecified, lists active project, if available.
---@return string[]
function M.list(opts)
  opts = opts or {}
  local ctx = render_autosession_context(opts.cwd or assert(util.auto.cwd_init()))
  if ctx then
    return Core.list({ dir = ctx.project.data_dir })
  end
  return {}
end

---List all known projects.
---@return string[]
function M.list_projects()
  --TODO: This is quite inefficient and could benefit from an inventory somewhere.
  local projects = {}

  local continuity_dir = util.path.get_session_dir(Config.autosession.dir)
  for name, typ in vim.fs.dir(continuity_dir) do
    if typ == "directory" then
      local save_file = vim.fs.find(function(fname)
        return fname:match(".*%.json$")
      end, { limit = 1, path = util.path.join(continuity_dir, name) })
      if save_file[1] then
        local save_contents = util.path.load_json_file(save_file[1])
        local cwd = save_contents.global.cwd
        if util.path.exists(cwd) then
          local ctx = render_autosession_context(cwd)
          if ctx then
            projects[#projects + 1] = ctx.project.name
          end
        end
      end
    end
  end
  return projects
end

---Dev helper currently (beware: unstable/inefficient).
---When changing the mapping from workspace to project name, all previously
---saved states would be lost. This tries to migrate state data to the new mapping,
---cleans projects whose cwd does not exist anymore or which are disabled
---Caution! This does not account for projects with multiple associated directories/sessions!
---Checks the first session's cwd/enabled state only!
function M.migrate_projects()
  local ret = {
    broken = {},
    missing = {},
    skipped = {},
    migrated = {},
    deactivated = {},
    duplicate = {},
    errors = {},
  }

  local function rm(dir, scope, root)
    local ok, msg = pcall(util.path.rmdir, dir, { recursive = true })
    if ok then
      table.insert(ret[scope], { root = root, old_dir = dir })
    else
      table.insert(ret.errors, { type = scope, root = root, old_dir = dir, msg = msg })
    end
  end

  local function mv(old, new, root, new_name)
    if util.path.exists(new) then
      table.insert(ret.errors, {
        type = "migration",
        root = root,
        old_dir = old,
        new_dir = new,
        msg = "Target project exists, cannot merge",
      })
      -- rm(old, "duplicate", root)
    else
      local ok, msg = pcall(os.rename, old, new)
      if ok then
        table.insert(ret.migrated, {
          root = root,
          new_name = new_name,
        })
      else
        table.insert(ret.errors, {
          type = "migration",
          root = root,
          new_name = new_name,
          old_dir = old,
          new_dir = new,
          msg = msg,
        })
      end
    end
  end

  local continuity_dir = util.path.get_session_dir(Config.autosession.dir)
  for name, typ in vim.fs.dir(continuity_dir) do
    if typ == "directory" then
      local project_dir = util.path.join(continuity_dir, name)
      local save_file = vim.fs.find(function(fname)
        return fname:match(".*%.json$")
      end, { limit = 1, path = project_dir })
      if save_file[1] then
        local save_contents = util.path.load_json_file(save_file[1])
        local cwd = save_contents.global.cwd
        if not cwd or cwd == "" or vim.fn.isabsolutepath(cwd) == 0 then
          rm(project_dir, "broken", cwd)
        elseif util.path.exists(cwd) then
          local ctx = render_autosession_context(cwd)
          if ctx then
            if not ctx.project.data_dir:find(name, nil, true) then
              local new_dir = util.path.join(continuity_dir, util.auto.hash(ctx.project.name))
              mv(project_dir, new_dir, cwd, ctx.project.name)
            else
              table.insert(ret.skipped, { root = cwd, name = ctx.project.name })
            end
          else
            -- FIXME: This would delete related sessions, not sure if sensible for a broader application
            rm(project_dir, "deactivated", cwd)
          end
        else
          rm(project_dir, "missing", cwd)
        end
      end
    end
  end
  return ret
end

---Return info about the currently active autosession.
---@return {current_session: continuity.Autosession|false, current_session_data?: table}
function M.info()
  local cur = current_autosession()
  return {
    current_session = cur or false,
    current_session_data = cur
      and util.path.load_json_file(util.path.get_session_file(cur.name, cur.project.data_dir)),
  }
end

--- Just sets `vim.g.continuity_config`, which you can do yourself
--- without calling this function if you so desire.
--- The config is applied once any function in the `continuity` or `continuity.core`
--- modules is called, which unsets the global variable again.
--- Future writes to the global variable are recognized and result in a complete config reset,
--- meaning successive writes to the global variable do not build on top of each other.
--- If you need to force application of the passed config eagerly, pass it
--- to `continuity.config.setup` instead, which parses and applies the configuration immediately.
---@param opts continuity.UserConfig?
function M.setup(opts)
  vim.g.continuity_config = opts
end

return util.lazy_setup_wrapper(M)

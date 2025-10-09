-- Setup autoloading and autosaving of sessions per project.

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
local Session = lazy_require("continuity.core.session")
local Snapshot = lazy_require("continuity.core.snapshot")
local log = lazy_require("continuity.log")

-- Monitor the currently active branch and check if we need to reload when it changes
---@type string?
local last_head
-- When an autosession is active, the augroup that monitors for changes (git branch, global cwd)
-- to automatically save and reload when necessary
---@type integer?
local monitor_group

---@class continuity.auto
local M = {}

---@namespace continuity.auto
---@using continuity.core

---@generic T: Session.Target
---@param session ActiveSession<T>
---@return TypeGuard<ActiveAutosession<T>>
local function is_autosession(session)
  return not not (session.meta and session.meta.autosession)
end

--- Return the autosession context if there is an attached session and it's an autosession.
---@generic T: Session.Target
---@return ActiveAutosession<T>?
---@return AutosessionContext?
local function current_autosession()
  local cur = Session.get_global()
  if not cur or not is_autosession(cur) then
    return
  end
  ---@cast cur.meta -nil
  return cur, cur.meta.autosession
end

--- Merge save/load opts for passing into core funcs.
---@generic T: (SaveOpts & PassthroughOpts|LoadOpts & PassthroughOpts)?
---@param opts? T Opts passed to the function
---@param cur ActiveAutosession|AutosessionContext Autosession to operate on
---@param defaults? T Call-specific defaults
---@param forced? table<string, any> Call-specific forced params
---@return T - nil
local function core_opts(opts, cur, defaults, forced)
  cur = (cur.meta and cur.meta.autosession) or cur
  return vim.tbl_extend(
    "force",
    Config.autosession.config --[[@as table]],
    defaults or {},
    cur.config --[[@as table]],
    opts or {},
    forced or {},
    { meta = { autosession = cur } }
  )
end

---@param cwd string
---@return AutosessionContext?
local function get_ctx(cwd)
  local spec = Config.autosession.spec(cwd)
  if not spec then
    return spec
  end
  if not spec.project.data_dir or spec.project.data_dir == "" then
    spec.project.data_dir = util.path.join(
      util.path.get_session_dir(Config.autosession.dir),
      util.path.escape(spec.project.name)
    )
  elseif vim.fn.isabsolutepath(spec.project.data_dir) == 0 then
    spec.project.data_dir =
      util.path.join(util.path.get_session_dir(Config.autosession.dir), spec.project.data_dir)
  end
  ---@cast spec AutosessionContext
  spec.cwd = cwd
  return spec
end

---@type fun(autosession: AutosessionContext?)
local monitor

---Save the currently active autosession.
---@param opts? SaveOpts & PassthroughOpts
function M.save(opts)
  local cur = current_autosession()
  if not cur then
    return
  end
  opts = core_opts(opts, cur, { attach = true, notify = false })
  -- TODO: Update the session config?
  if not cur:save(opts) then
    -- We attempted to save the session while a snapshot was being restored
    return
  end
  if not opts.attach then
    cur:detach("save", opts)
  end
end

--- Detach from the currently active autosession.
--- If autosave is enabled, save it. Optionally closes everything.
---@param opts? Session.DetachOpts & PassthroughOpts Parameters for continuity.core.session.detach
function M.detach(opts)
  local cur = current_autosession()
  if not cur then
    return
  end
  cur:detach("request", opts or {})
end

---Load an autosession.
---@param autosession? AutosessionContext|string The autosession table as rendered by render_autosession_context or cwd to pass to it
---@param opts? LoadOpts
function M.load(autosession, opts)
  if type(autosession) == "string" then
    autosession = get_ctx(autosession)
  end
  monitor(autosession)
  if not autosession then
    return
  end

  local load_opts = core_opts(opts, autosession, { attach = true, reset = true })
  -- We only allow global autosessions at the moment, which would be reset when reset == "auto"
  load_opts.reset = not not load_opts.reset
  ---@cast load_opts LoadOptsParsed & PassthroughOpts
  log.fmt_debug(
    "Loading autosession %s with opts %s.\nData: %s",
    autosession.name,
    load_opts,
    autosession
  )

  local session_file, state_dir, context_dir =
    util.path.get_autosession_paths(autosession.name, autosession.project.data_dir)

  local session
  if util.path.exists(session_file) then
    local snapshot
    session, snapshot =
      Session.from_snapshot(autosession.name, session_file, state_dir, context_dir, load_opts)
    if not session or not snapshot then
      -- This is an edge case, we made sure the file existed and the call above would usually error
      log.fmt_error(
        "Failed loading autosession {} in project {}. Consider deleting the saved snapshot at {}.",
        autosession.name,
        autosession.project.name,
        session_file
      )
      return
    end
    if load_opts.reset then
      Session.detach_all("load", load_opts)
    else
      Session.detach("__global", "load", load_opts)
    end
    session = session:restore(load_opts, snapshot)
  else
    if not load_opts.attach then
      -- The autosession is used to setup a default view instead of session persistence,
      -- but the referenced session does not exist.
      log.fmt_error(
        "Could not find autosession {} in project {}, cannot start a new one because attach was set to false. "
          .. "Ensure the session file exists if you configure autloading sessions without attaching after.",
        autosession.name,
        autosession.project.name
      )
      return
    end
    if load_opts.reset then
      Session.detach_all("load", { save = load_opts.save, reset = true })
      -- This would usually be done by snapshot restoration, but we're not restoring anything now
      require("continuity.core.layout").close_everything()
    else
      Session.detach("__global", "load", { save = load_opts.save })
    end
    -- The session did not exist, need to save to initialize an empty one.
    -- First, change cwd to workspace root since we're saving/restoring cwd.
    vim.api.nvim_set_current_dir(autosession.root)
    session = Session.create_new(autosession.name, session_file, state_dir, context_dir, {
      autosave_enabled = load_opts.autosave_enabled,
      autosave_interval = load_opts.autosave_interval,
      autosave_notify = load_opts.autosave_notify,
      on_attach = load_opts.on_attach,
      on_detach = load_opts.on_detach,
      buf_filter = load_opts.buf_filter,
      modified = load_opts.modified,
      options = load_opts.options,
      tab_buf_filter = load_opts.tab_buf_filter,
      meta = load_opts.meta,
    })
  end
  session = session:attach()
end

---If an autosession is active, save it and detach. Then try to start a new one.
function M.reload()
  log.fmt_trace("Reload called. Checking if we need to reload")
  local effective_cwd = util.auto.cwd()
  local autosession = get_ctx(effective_cwd)
  local cur = current_autosession() or nil
  ---@cast cur ActiveAutosession?
  if not autosession then
    if cur then
      log.fmt_trace("Reload check result: New context disables active autosession")
      cur:detach("auto_reload", { reset = true })
    else
      log.fmt_trace(
        "Reload check result: No active autosession, new context is disabled as well. Nothing to do."
      )
    end
    return
  end
  if
    cur
    and cur.meta.autosession.project.name == autosession.project.name
    and cur.name == autosession.name
  then
    log.fmt_trace(
      "Reload check result: Not reloading because new context has same project and session name as active session"
    )
    return
  end
  log.fmt_trace("Reloading. Current session:\n%s\nNew session:\n%s", cur or "nil", autosession)
  -- FIXME: This could be the whole call. Currently, this doesn't reconfigure monitoring when
  --      disabling an autosession. Need to think about the semantics.
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

-- Create hooks that:
---1. When the session is associated with a git repo and gitsigns is available, save/detach/reload active autosession on branch changes.
---2. When the global CWD changes, save/detach/reload active autosession.
---@param autosession? AutosessionContext The active autosession that should be monitored
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
    -- if we're here, autosession_head is defined and thus project.repo is as well
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
          -- TODO: If we're autoclosing a session with buffer changes, they might get lost
          --       if not saving modifications. Ask before? :)
          M.reload()
        end
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
      -- FIXME: This should detach non-autosessions as well
      local cur = Session.get_global()
      if not cur or not is_autosession(cur) or Snapshot.is_loading() then
        -- We don't need to detach if we don't have an active session or
        -- if we're in the process of loading one
        return
      end
      ---@cast cur ActiveAutosession
      ---@diagnostic disable-next-line: undefined-field
      local lookahead = get_ctx(vim.v.event.directory)
      if
        not lookahead
        or cur.meta.autosession.project.name ~= lookahead.project.name
        or cur.name ~= lookahead.name
      then
        log.fmt_trace(
          "DirChangedPre: Need to detach because session is going to change. Current session:\n%s\nNew session:\n%s",
          cur,
          lookahead or "nil"
        )
        -- We're going to switch/disable the active autosession.
        -- Ensure we detach before the global cwd is changed, otherwise
        -- we would override the current session's intended cwd with the new one.
        cur:detach("auto_dirchange", { reset = true })
      end
    end,
    group = monitor_group,
  })
  vim.api.nvim_create_autocmd("DirChanged", {
    pattern = "global",
    callback = function()
      if not Snapshot.is_loading() then
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
---@param cwd? string The working directory to switch to before starting autosession. Defaults to nvim's process' cwd.
---@param opts? LoadOpts
function M.start(cwd, opts)
  M.load(cwd or util.auto.cwd(), opts)
end

---Stop Continuity:
---1. If we're inside an active autosession, save it and detach. Does not close everything by default.
---2. In any case, stop monitoring for directory or branch changes.
function M.stop()
  stop_monitoring()
  M.detach({ reset = false })
end

---Reset the currently active autosession. Closes everything.
---@param opts? ResetOpts Options to influence execution
function M.reset(opts)
  local cur = current_autosession()
  if not cur then
    return
  end
  opts = vim.tbl_extend("force", { notify = false }, opts or {})
  cur:detach("delete", { reset = true })
  cur:delete({ notify = opts.notify, silence_errors = opts.silence_errors })
  if opts.reload ~= false then
    M.reload()
  end
end

---Remove all autosessions associated with a project.
---If the target is the active project, resets current session as well and closes everything.
---@param opts? {name?: string, force?: boolean} Specify the project to reset. If unspecified, resets active project, if available.
function M.reset_project(opts)
  opts = opts or {}
  local name = opts.name
  local project_dir
  local _, cur = current_autosession()
  if not name then
    if not cur then
      return
    end
    name = cur.project.name
    project_dir = cur.project.data_dir
  end
  if not project_dir then
    local continuity_dir = util.path.get_session_dir(Config.autosession.dir)
    project_dir = util.path.join(continuity_dir, util.path.escape(name))
  end
  if not util.path.exists(project_dir) then
    return
  end

  local expected_parent = util.path.get_stdpath_filename("data", Config.autosession.dir)
  if not opts.force then
    -- sanity check before recursively deleting
    assert(
      project_dir:sub(1, #expected_parent) == expected_parent,
      (
        "Rendered project data dir (%s) is not in Continuity's autosession data dir (%s), "
        .. "refusing to recursively delete directory. Pass force=true to skip this check"
      ):format(project_dir, expected_parent)
    )
  end

  local resetting_active = false
  -- If we're resetting the active project, ensure we detach from the active session before deleting the data
  if cur and project_dir == cur.project.data_dir then
    M.reset({ reload = false })
    resetting_active = true
  end

  util.path.rmdir(project_dir, { recursive = true })

  if resetting_active then
    M.reload()
  end
end

---List autosessions associated with a project.
---@param opts? {cwd?: string, project_dir?: string, project_name?: string} Specify the project to list. If unspecified, lists active project, if available.
---@return string[]
function M.list(opts)
  opts = opts or {}
  local project_dir = opts.project_dir
  if not project_dir and opts.project_name then
    project_dir = util.path.get_autosession_project_dir(opts.project_name, Config.autosession.dir)
  end
  if not (project_dir or opts.cwd) then
    local _, cur = current_autosession()
    if cur then
      project_dir = cur.project.data_dir
    end
  end
  if not project_dir then
    local rendered = get_ctx(opts.cwd or util.auto.cwd())
    if not rendered then
      return {}
    end
    project_dir = rendered.project.data_dir
  end
  if not util.path.exists(project_dir) then
    return {}
  end
  return util.path.ls(project_dir, function(entry)
    if entry.type ~= "file" then
      return
    end
    local encoded = entry.name:match("^(.+)%.json$")
    return encoded and util.path.unescape(encoded) or nil
  end, Config.load.order)
end

---List all known projects.
---@param opts? {with_sessions?: boolean} Optionally list all known sessions for all known projects as well.
---@return string[]
function M.list_projects(opts)
  opts = opts or {}
  local projects_dir = util.path.get_stdpath_filename("data", Config.autosession.dir)
  local res = util.path.ls(projects_dir, function(entry, dir)
    if entry.type ~= "directory" or entry.name == "__state" then
      return
    end
    local project_name = util.path.unescape(entry.name)
    return opts.with_sessions and { project_name, util.path.join(dir, entry.name) } or project_name
  end, Config.load.order)
  if opts.with_sessions then
    return vim.iter(res):fold({}, function(acc, v)
      acc[v[1]] = M.list({ project_dir = v[2] })
      return acc
    end)
  end
  return res
end

---Dev helper currently (beware: unstable/inefficient).
---When changing the mapping from workspace to project name, all previously
---saved states would be lost. This tries to migrate state data to the new mapping,
---cleans projects whose cwd does not exist anymore or which are disabled
---Caution! This does not account for projects with multiple associated directories/sessions!
---Checks the first session's cwd/enabled state only!
---@param opts MigrateProjectsOpts? Options for migration. You need to pass `{dry_run = false}` for this function to have an effect.
---@return table<"broken"|"missing"|"skipped"|"migrated"|"deactivated"|"duplicate"|"empty"|"errors", table[]>
function M.migrate_projects(opts)
  opts = opts or {}
  opts.dry_run = opts.dry_run ~= false
  if not opts.old_root or opts.old_root == "" then
    opts.old_root = util.path.get_session_dir(Config.autosession.dir)
  elseif vim.fn.isabsolutepath(opts.old_root) == 0 then
    opts.old_root = util.path.get_session_dir(opts.old_root)
  end

  local ret = {
    broken = {},
    missing = {},
    skipped = {},
    migrated = {},
    deactivated = {},
    duplicate = {},
    empty = {},
    errors = {},
  }

  local function rm(dir, scope, root)
    local ok, msg
    if not opts.dry_run then
      ok, msg = pcall(util.path.rmdir, dir, { recursive = true })
    end
    if opts.dry_run or ok then
      table.insert(ret[scope], { root = root, old_dir = dir })
    else
      table.insert(ret.errors, { type = scope, root = root, old_dir = dir, msg = msg })
    end
  end

  local function mv(old, new, root, new_name)
    local res = false
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
      local ok, msg
      if not opts.dry_run then
        ok, msg = pcall(os.rename, old, new)
      end
      if opts.dry_run or ok then
        res = true
        table.insert(ret.migrated, {
          root = root,
          new_name = new_name,
          old_dir = old,
          new_dir = new,
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
    return res
  end

  local function mv_session(dir, name, old, new)
    local src, tgt = util.path.join(dir, old), util.path.join(dir, new)
    if util.path.exists(tgt) then
      table.insert(ret.errors, {
        type = "session_migration",
        root = dir,
        old_file = old,
        new_file = new,
        msg = "Target session exists",
      })
      return
    end
    local ok, msg
    if not opts.dry_run then
      ok, msg = pcall(os.rename, src, tgt)
    end
    if opts.dry_run or ok then
      res = true
      ret.migrated[#ret.migrated].sessions = ret.migrated[#ret.migrated].sessions or {}
      ret.migrated[#ret.migrated].sessions[#ret.migrated[#ret.migrated].sessions + 1] =
        { name = name, old = old, new = new }
    else
      table.insert(ret.errors, {
        type = "session_migration",
        root = dir,
        old_file = old,
        new_file = new,
        msg = msg,
      })
    end
  end

  for name, typ in vim.fs.dir(opts.old_root) do
    if typ == "directory" then
      local project_dir = util.path.join(opts.old_root, name)
      local save_files = util.path.ls(project_dir, function(entry, _)
        if entry.type ~= "file" then
          return
        end
        local serialized_name = entry.name:match("^(.*)%.json$")
        if not serialized_name then
          return
        end
        local deserialized_name = serialized_name:gsub("^([a-z]+_)", function(v)
          return vim.tbl_contains({ "feat_", "fix_", "renovate_" }, v) and (v:gsub("_$", "/")) or v
        end)
        return {
          deserialized_name,
          serialized_name .. ".json",
          util.path.escape(deserialized_name) .. ".json",
        }
      end)
      if #save_files == 1 and save_files[1][1] == "" then
        save_files = {}
      end
      if save_files[1] then
        local save_contents =
          util.path.load_json_file(util.path.join(project_dir, save_files[1][2]))
        local cwd = save_contents.global.cwd
        if not cwd or cwd == "" or vim.fn.isabsolutepath(cwd) == 0 then
          rm(project_dir, "broken", cwd)
        elseif util.path.exists(cwd) then
          local ctx = get_ctx(cwd)
          if ctx then
            if ctx.project.data_dir ~= project_dir then
              if mv(project_dir, ctx.project.data_dir, cwd, ctx.project.name) then
                for _, session in ipairs(save_files) do
                  if session[2] ~= session[3] then
                    mv_session(
                      opts.dry_run and project_dir or ctx.project.data_dir,
                      unpack(session)
                    )
                  elseif session[1] == "" then
                    rm(
                      util.path.join(opts.dry_run and project_dir or ctx.project.data_dir, ".json"),
                      "broken",
                      cwd
                    )
                  end
                end
              end
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
      else
        rm(project_dir, "empty")
      end
    end
  end
  return ret
end

--- Return information about the currently active session.
--- Includes autosession information, if it is an autosession.
---@param opts {with_snapshot?: boolean}?
---@return ActiveAutosessionInfo?
function M.info(opts)
  local cur = Session.get_global()
  if not cur then
    return
  end
  opts = opts or {}
  local core_info = cur:info()
  local is_auto = false
  local autosession_config, autosession_data
  if cur and is_autosession(cur) then
    ---@cast cur ActiveAutosession
    is_auto = true
    autosession_config = cur.meta.autosession
    autosession_data = opts.with_snapshot
      and util.path.load_json_file(
        util.path.get_autosession_file(cur.name, autosession_config.project.data_dir)
      )
  end
  ---@type ActiveAutosessionInfo
  local res = vim.tbl_extend("error", core_info, {
    is_autosession = is_auto,
    autosession_config = autosession_config,
    autosession_data = autosession_data,
  })
  return res
end

return util.lazy_setup_wrapper(M)

local Config = require("continuity.config")
local Session = require("continuity.core.session")
local util = require("continuity.util")

--- Interactive API, compatible with stevearc/resession.nvim.
---@class continuity.core
local M = {}

---@namespace continuity

---@param tab_scoped boolean?
---@return string?
local function get_save_name(tab_scoped)
  local current
  if tab_scoped then
    current = Session.get_tabnr()
  else
    current = Session.get_global()
  end
  if current then
    return current.name
  end
  local name
  vim.ui.input({ prompt = "Session name" }, function(selected)
    name = selected
  end)
  return name
end

--- Get a session with the specified configuration. If a session with this configuration
--- (name + session_file + state_dir + tabnr) exists, update its other options and return it,
--- otherwise create a new one.
---@generic T: SessionTarget
---@overload fun(name: string, opts: LoadOpts|SaveOpts, tabnr: nil): IdleSession<GlobalTarget>, TypeGuard<ActiveSession<T>>
---@overload fun(name: string, opts: LoadOpts|SaveOpts, tabnr: TabNr): IdleSession<TabTarget>, TypeGuard<ActiveSession<T>>
---@overload fun(name: string, opts: LoadOpts|SaveOpts, tabnr: nil): ActiveSession<GlobalTarget>, TypeGuard<ActiveSession<T>>
---@overload fun(name: string, opts: LoadOpts|SaveOpts, tabnr: TabNr): ActiveSession<TabTarget>, TypeGuard<ActiveSession<T>>
---@param name string
---@param opts LoadOpts|SaveOpts
---@param tabnr? TabNr
---@return IdleSession<T>|ActiveSession<T> session
---@return TypeGuard<ActiveSession<T>> attached
local function get_session(name, opts, tabnr)
  local attached = Session.get_named(name)
  -- emmylua 0.13 seems to choke on these expressions
  local session_file, state_dir = util.path.get_session_paths(name, opts.dir or Config.session.dir) ---@diagnostic disable-line: param-type-not-match
  if
    not attached
    or attached.tabnr ~= tabnr
    or attached.session_file ~= session_file
    or attached.state_dir ~= state_dir
  then
    return Session.create_new(name, session_file, state_dir, opts, tabnr), false
  end
  attached:update(opts)
  return attached, true
end

--- Check if a session with this configuration is already attached and return it if so
---@generic T: SessionTarget
---@overload fun(name: string, opts: LoadOpts|SaveOpts, tabnr: nil): ActiveSession<GlobalTarget>?
---@overload fun(name: string, opts: LoadOpts|SaveOpts, tabnr: TabNr): ActiveSession<TabTarget>
---@param name string
---@param opts LoadOpts|SaveOpts|DeleteOpts|DetachOpts
---@param tabnr? TabNr|boolean
---@return ActiveSession<T>?
local function find_attached(name, opts, tabnr)
  local attached = Session.get_named(name)
  if not attached then
    return
  end
  -- emmylua 0.13 seems to choke on this expression
  local session_file, state_dir = util.path.get_session_paths(name, opts.dir or Config.session.dir) ---@diagnostic disable-line: param-type-not-match
  if
    (tabnr == false or attached.tabnr == tabnr)
    and attached.session_file == session_file
    and attached.state_dir == state_dir
  then
    return attached
  end
end

--- Save the current global or tabpage state to a named session.
---@param name string The name of the session
---@param opts? SaveOpts
---@param target_tabpage? TabNr Instead of saving everything, only save the current tabpage
local function save(name, opts, target_tabpage)
  ---@type SaveOpts
  opts = vim.tbl_extend("keep", opts or {}, {
    notify = true,
    attach = true,
  })
  local session, attached = get_session(name, opts, target_tabpage)
  if not session:save({ notify = opts.notify }, { attach = opts.attach, reset = opts.reset }) then
    return
  end
  -- Detach behavior differences to Resession:
  --   * For tabpage save, Resession always detaches the global session + a session with the same name here, (re-)attaches afterwards.
  --   * For global save, Resession always detaches all tabpage ones and attaches/detaches the global one afterwards.
  -- We use the same handling for both types:
  --   * With attach=true, we only detach any session with the same name if it's not saved to the same file/of the same type. We also leave the other type untouched.
  --   * With attach=false, we only detach any session with the same name if is saved to the same file and of the same type.
  -- In essence, we allow both session types to coexist here and avoid detaching and then reattaching the same session since we have autosave behavior.
  -- We also don't detach when the current session is saved to another directory with the same name, e.g. as a backup.
  -- (Resession allows coexistence only when loading a global session with reset=false while a tabpage one is attached, but detaches the tabpage one if the global one is saved).
  -- TODO: Consider exposing the session object for better customizability of this somewhat implicit behavior and getting rid of `dir` in session logic.
  --       Then refactor the user API for manual sessions into a dedicated module with this logic.
  -- TODO: Improve the handling of simultaneous session types.
  if attached ~= opts.attach then
    local existing = Session.get_named(name)
    if existing then
      existing:detach("save", { reset = opts.reset })
    end
  end
  if opts.attach then
    -- written for type checking, otherwise just session:attach()
    session = session:attach()
  end
end

--- Save the current global state to disk
---@param name? string Name of the session
---@param opts? SaveOpts
function M.save(name, opts)
  name = name or get_save_name(false)
  if not name then
    return
  end
  save(name, opts)
end

--- Save the state of the current tabpage to disk
---@param name? string Name of the tabpage session. If not provided, will prompt user for session name
---@param opts? SaveOpts
function M.save_tab(name, opts)
  name = name or get_save_name(true)
  if not name then
    return
  end
  save(name, opts, vim.api.nvim_get_current_tabpage())
end

M.save_all = Session.save_all

---@param opts? LoadOpts
local function get_load_name(opts)
  local sessions = M.list({ dir = opts and opts.dir or nil })
  if vim.tbl_isempty(sessions) then
    vim.notify("No saved sessions", vim.log.levels.WARN)
    return
  end
  local select_opts = { kind = "resession_load", prompt = "Load session" }
  if Config.load.detail then
    local session_data = {}
    for _, session_name in ipairs(sessions) do
      local filename =
        util.path.get_session_file(session_name, opts and opts.dir or Config.session.dir)
      local data = util.path.load_json_file(filename)
      session_data[session_name] = data
    end
    select_opts.format_item = function(session_name)
      local data = session_data[session_name]
      local formatted = session_name
      if data then
        if data.tab_scoped then
          local tab_cwd = data.tabs[1].cwd
          formatted = formatted .. string.format(" (tab) [%s]", util.path.shorten_path(tab_cwd))
        else
          formatted = formatted .. string.format(" [%s]", util.path.shorten_path(data.global.cwd))
        end
      end
      return formatted
    end
  end
  local name
  vim.ui.select(sessions, select_opts, function(selected)
    name = selected
  end)
  return name
end

--- Load a session
---@param name? string
---@param opts? LoadOpts
---    attach? boolean Stay attached to session after loading (default true)
---    reset? boolean|"auto" Close everything before loading the session (default "auto")
---    silence_errors? boolean Don't error when trying to load a missing session
---    dir? string Name of directory to load from (overrides config.dir)
---@note
--- The default value of `reset = "auto"` will reset when loading a normal session, but _not_ when
--- loading a tab-scoped session.
function M.load(name, opts)
  opts = opts or {}
  name = name or get_load_name(opts)
  if not name then
    return
  end
  local session_file, state_dir = util.path.get_session_paths(name, opts.dir or Config.session.dir)
  local session, snapshot = Session.from_snapshot(name, session_file, state_dir, opts)
  if not session then
    return
  end
  -- If we're going to possibly switch sessions, detach _before_ loading a new session.
  -- This is in contrast to resession, which does this implicitly after loading the new one.
  -- We need to do it eagerly because autosave is baked into the detach logic.
  -- TODO: Consider optionally keeping persistent tab sessions
  if opts.reset == true or (opts.reset == "auto" and not session.tab_scoped) then
    -- We're going to close everything, detach both global and all tab scoped sessions.
    -- Autosave would not be triggered otherwise.
    for _, attached in ipairs(Session.get_all()) do
      attached:detach("load", { reset = true, save = opts.detach_save })
    end
    -- Possible leftovers will be closed in snapshot restoration
  elseif opts.attach and not session.tab_scoped then
    -- Difference to Resession:
    -- If we're loading a new global session, detach a previous one.
    -- This means we're keeping a global session and tabpage-scoped ones at the same time.
    -- Resession always detaches a global session, even when only loading a tabpage-scoped one.
    -- It does not however detach all tabpage-scoped ones when loading a global one without reset.
    -- TODO: Think about implications and the general interplay between global and tab-scoped sessions.
    local current_global = Session.get_global()
    if current_global then
      current_global:detach("load", { save = opts.detach_save })
    end
  end
  -- Ensure we don't have an existing session named the same as the new one.
  -- TODO: Consider erroring instead? This is somewhat undefined since detaching
  --       after loading the same session's file might have triggered autosave,
  --       but the loaded contents are from before the save.
  --       Seems like implicit, but expected behavior? It might desync modified buffers though.
  local name_clash = Session.get_named(name)
  if name_clash then
    name_clash:detach("load", { save = opts.detach_save })
  end
  session = session:restore(opts, snapshot)
  if opts.attach then
    session = session:attach()
  end
end

-- M.get_current = Manager.get_current
-- M.get_current_data = Manager.get_current_data
M.detach = Session.detach

--- List all available saved sessions
---@param opts? ListOpts
---@return string[]
function M.list(opts)
  opts = opts or {}
  local session_dir = util.path.get_session_dir(opts.dir or Config.session.dir)
  if not util.path.exists(session_dir) then
    return {}
  end
  return util.path.ls(session_dir, function(entry)
    return entry.type == "file" and entry.name:match("^(.+)%.json$")
  end, Config.load.order)
end

local function get_delete_name(opts)
  local sessions = M.list({ dir = opts and opts.dir })
  if vim.tbl_isempty(sessions) then
    vim.notify("No saved sessions", vim.log.levels.WARN)
    return
  end
  vim.ui.select(
    sessions,
    { kind = "resession_delete", prompt = "Delete session" },
    function(selected)
      if selected then
        M.delete(selected, { dir = opts.dir })
      end
    end
  )
end

--- Delete a saved session
---@param name? string Name of the session. If not provided, prompt for session to delete
---@param opts? DeleteOpts
function M.delete(name, opts)
  opts = opts or {}
  name = name or get_delete_name(opts)
  if not name then
    return
  end
  local attached = true
  local session = find_attached(name, opts, false)
  if not session then
    local session_file, state_dir =
      util.path.get_session_paths(name, opts.dir or Config.session.dir)
    session, attached = Session.create_new(name, session_file, state_dir, {}, nil), false
  end
  session:delete({ notify = opts.notify, silence_errors = opts.silence_errors })
  if attached then
    session:detach("delete", { reset = opts.reset })
  end
end

local autosave_group
function M.setup()
  autosave_group = vim.api.nvim_create_augroup("ContinuityAutosave", { clear = true })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = autosave_group,
    callback = function()
      -- Trigger detach, which in turn triggers autosave for sessions that have it enabled.
      M.detach(nil, "quit")
    end,
  })
end

return util.lazy_setup_wrapper(M)

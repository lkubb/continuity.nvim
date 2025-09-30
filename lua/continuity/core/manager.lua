local Config = require("continuity.config")
local util = require("continuity.util")

local lazy_require = util.lazy_require
local Ext = lazy_require("continuity.core.ext")
local Snapshot = lazy_require("continuity.core.snapshot")
local log = lazy_require("continuity.log")

---@diagnostic disable-next-line: deprecated
local uv = vim.uv or vim.loop

---@class continuity.core.session
local M = {}

local current_session ---@type string?
local tab_sessions = {} ---@type table<continuity.TabNr, string?>
local sessions = {} ---@type table<string, continuity.Session?>

---@class continuity.Session: continuity.SessionConfig:
---@field name string
---@field tabnr? continuity.TabNr The tab this session is attached to, if any.
---@field _aug integer? Neovim augroup for this session, if it's attached
---@field _timer uv.uv_timer_t? Autosave timer
---@field _on_attach continuity.AttachHook[]
---@field _on_detach continuity.DetachHook[]
local Session = {}
Session.__index = Session

---@param name string
---@param opts continuity.LoadOpts|continuity.SaveOpts
---@param tabnr? continuity.TabNr
---@return continuity.Session
---@return boolean Whether this specific session is already attached
function Session.get(name, opts, tabnr)
  local existing = sessions[name]
  if not existing or existing.tabnr ~= tabnr then
    return Session.new(name, opts, tabnr), false
  end
  -- emmylua 0.13 seems to choke on these expressions
  local session_file = util.path.get_session_file(name, opts.dir or Config.session.dir) ---@diagnostic disable-line: param-type-not-match
  local state_dir = util.path.get_session_state_dir(name, opts.dir or Config.session.dir) ---@diagnostic disable-line: param-type-not-match
  if existing.session_file ~= session_file or existing.state_dir ~= state_dir then
    return Session.new(name, opts, tabnr, session_file, state_dir), false
  end
  existing:update(opts)
  return existing, true
end

---@param name string
---@param opts continuity.LoadOpts|continuity.SaveOpts
---@param tabnr? continuity.TabNr
---@param session_file? string
---@param state_dir? string
---@return continuity.Session
function Session.new(name, opts, tabnr, session_file, state_dir)
  session_file = session_file or util.path.get_session_file(name, opts.dir or Config.session.dir) ---@diagnostic disable-line: param-type-not-match
  state_dir = state_dir or util.path.get_session_state_dir(name, opts.dir or Config.session.dir) ---@diagnostic disable-line: param-type-not-match
  local autosave_enabled = opts.autosave_enabled
  -- "ternary" expression does not work when false is a valid value, need to pre-define for below
  if autosave_enabled == nil then
    autosave_enabled = Config.session.autosave_enabled
  end
  ---@type continuity.SessionConfig
  local config = {
    -- continuity.SessionConfig part
    session_file = session_file,
    state_dir = state_dir,
    -- We need to query defaults for these values during load since we cannot
    -- dynamically reconfigure them easily
    autosave_enabled = autosave_enabled,
    autosave_interval = opts.autosave_interval or Config.session.autosave_interval,
    autosave_notify = opts.autosave_notify,
    meta = opts.meta,
    -- continuity.SnapshotOpts part
    modified = opts.modified,
    -- These can be defined even when loading to be able to configure autosave settings.
    -- They currently don't affect loading though.
    options = opts.options,
    buf_filter = opts.buf_filter,
    tab_buf_filter = opts.tab_buf_filter,
    -- internals
    name = name,
    tabnr = tabnr,
    _on_attach = {},
    _on_detach = {},
  }
  local self = setmetatable(config, Session)
  if opts.on_attach then
    self:add_hook("attach", opts.on_attach)
  end
  if Config.session.on_attach then
    self:add_hook("attach", Config.session.on_attach)
  end
  if opts.on_detach then
    self:add_hook("detach", opts.on_detach)
  end
  if Config.session.on_detach then
    self:add_hook("detach", Config.session.on_detach)
  end
  return self
end

---@param opts continuity.LoadOpts|continuity.SaveOpts
function Session:update(opts)
  local update_autosave = false
  vim
    .iter({
      "autosave_enabled",
      "autosave_interval",
      "autosave_notify",
      "meta",
      "modified",
      "options",
      "buf_filter",
      "tab_buf_filter",
    })
    :each(function(attr)
      if opts[attr] ~= nil and self[attr] ~= opts[attr] then
        self[attr] = opts[attr]
        if attr == "autosave_enabled" or attr == "autosave_interval" then
          update_autosave = true
        end
      end
    end)
  if opts.on_attach then
    self._on_attach = {}
    self:add_hook("attach", opts.on_attach)
    if Config.session.on_attach then
      self:add_hook("attach", Config.session.on_attach)
    end
  end
  if opts.on_detach then
    self._on_detach = {}
    self:add_hook("detach", opts.on_detach)
    if Config.session.on_detach then
      self:add_hook("detach", Config.session.on_detach)
    end
  end
  if self._aug and update_autosave then
    self:setup_autosave()
  end
end

---@param event "attach"|"detach"
---@param hook continuity.AttachHook|continuity.DetachHook
---@return self
function Session:add_hook(event, hook)
  local key = "_on_" .. event
  self[key][#self[key] + 1] = hook
  return self
end

function Session:setup_autosave()
  if self._timer then
    self._timer:stop()
    self._timer = nil
  end
  if self.autosave_enabled then
    self._timer = assert(uv.new_timer(), "Failed creating autosave timer")
    self._timer:start(
      self.autosave_interval * 1000,
      self.autosave_interval * 1000,
      vim.schedule_wrap(function()
        self:autosave()
      end)
    )
  end
end

function Session:attach()
  self._aug = vim.api.nvim_create_augroup("continuity__" .. self.name, { clear = true })
  if self.tabnr then
    tab_sessions[self.tabnr] = self.name
    vim.api.nvim_create_autocmd("TabClosed", {
      pattern = tostring(self.tabnr),
      callback = function()
        self:detach("tab_closed", {})
      end,
      once = true,
      group = self._aug,
    })
  else
    current_session = self.name
  end
  sessions[self.name] = self
  for _, hook in ipairs(self._on_attach) do
    hook(self)
  end
  self:setup_autosave()
end

---@param opts? continuity.SaveAllOpts
---@param hook_opts? {attach?: boolean, reset?: boolean} Options that need to be passed through to pre_save/post_save hooks.
function Session:save(opts, hook_opts)
  local save_opts =
    vim.tbl_extend("keep", self:save_opts(), hook_opts or {}, { attach = true, reset = false })
  if
    not Snapshot.save_as(
      self.name,
      save_opts,
      self.tabnr,
      save_opts.session_file,
      save_opts.state_dir
    )
  then
    return false
  end
  if (opts or {}).notify ~= false then
    vim.notify(string.format('Saved session "%s"', self.name))
  end
  return true
end

---@return continuity.SaveOpts
function Session:save_opts()
  return {
    -- Snapshot options
    modified = self.modified,
    options = self.options,
    buf_filter = self.buf_filter,
    tab_buf_filter = self.tab_buf_filter,
    -- Information for pre_save/post_save hooks
    -- 1. Session handling info
    autosave_enabled = self.autosave_enabled,
    autosave_interval = self.autosave_interval,
    autosave_notify = self.autosave_notify,
    -- 2. Metadata
    meta = self.meta,
    session_file = self.session_file,
    state_dir = self.state_dir,
  }
end

---@return continuity.AttachedSessionInfo
function Session:info()
  return {
    -- Snapshot options
    modified = self.modified,
    options = self.options,
    buf_filter = self.buf_filter,
    tab_buf_filter = self.tab_buf_filter,
    -- Session handling
    autosave_enabled = self.autosave_enabled,
    autosave_interval = self.autosave_interval,
    autosave_notify = self.autosave_notify,
    -- Metadata
    name = self.name,
    tabnr = self.tabnr,
    meta = self.meta,
    session_file = self.session_file,
    state_dir = self.state_dir,
  }
end

---@param opts? continuity.SaveAllOpts
---@param force? boolean
function Session:autosave(opts, force)
  if not (force or self.autosave_enabled) then
    return
  end
  opts = opts or {}
  local notify = opts.notify
  if notify == nil then
    notify = self.autosave_notify
    if notify == nil then
      notify = Config.session.autosave_notify
    end
  end
  self:save({ notify = notify })
end

---@param reason continuity.DetachReason
---@param opts continuity.DetachOpts
function Session:detach(reason, opts)
  if self.tabnr then
    assert(
      sessions[tab_sessions[self.tabnr]] == self,
      "Tried to detach unattached tab session, this is likely a bug"
    )
  else
    assert(
      sessions[current_session] == self,
      "Tried to detach global session that was not attached, this is likely a bug"
    )
  end
  assert(self._aug, "Session is not attached")
  if self._timer then
    self._timer:stop()
    self._timer = nil
  end
  for _, hook in ipairs(self._on_detach) do
    opts = hook(self, reason, opts) or opts
  end
  -- TODO: Rework save + detach workflow for attached sessions
  if (self.tabnr and reason == "tab_closed") or reason == "save" or reason == "delete" then
    -- The tab is already gone. "TabClosedPre" does not exist in neovim (yet?)
    opts.save = false
  elseif opts.save == nil then
    opts.save = self.autosave_enabled
  end
  if opts.save then
    local autosave_opts = {}
    if reason == "quit" then
      autosave_opts.notify = false
    end
    self:autosave(autosave_opts, true)
  end
  vim.api.nvim_del_augroup_by_id(self._aug)
  if opts.reset then
    if self.tabnr then
      if reason ~= "tab_closed" then
        vim.cmd.tabclose({ self.tabnr, bang = true })
      end
      -- TODO: Consider unloading associated buffers? (cave: should happen even on tab_closed)
    else
      -- TODO: Everything except tabs with associated sessions?
      require("continuity.core.layout").close_everything()
    end
  end
  if self.tabnr then
    tab_sessions[self.tabnr] = nil
  else
    current_session = nil
  end
  sessions[self.name] = nil
end

--- Mark a tab session as invalid (i.e. remembered as attached, but its tab is gone).
--- Removes associated resources.
function Session:forget()
  assert(self.tabnr, "Cannot forget global session")
  if self._aug then
    vim.api.nvim_del_augroup_by_id(self._aug)
    self._aug = nil
  end
  sessions[self.name] = nil
  tab_sessions[self.tabnr] = nil
end

---@param name string
---@return continuity.TabNr?
local function find_tabpage_for_session(name)
  for k, v in pairs(tab_sessions) do
    if v == name then
      return k
    end
  end
end

---@overload fun(by_name: true): table<string,continuity.TabNr?>
---@overload fun(by_name: false?): table<continuity.TabNr,string?>
---@param by_name? boolean
---@return table<string,continuity.TabNr?>|table<continuity.TabNr,string?>
local function list_active_tabpage_sessions(by_name)
  -- First prune tab-scoped sessions for closed tabs
  -- Note: Shouldn't usually be necessary because we're auto-detaching on TabClosed
  local invalid_tabpages = vim.tbl_filter(function(tabpage)
    return not vim.api.nvim_tabpage_is_valid(tabpage)
  end, vim.tbl_keys(tab_sessions))
  for _, tabpage in ipairs(invalid_tabpages) do
    sessions[tab_sessions[tabpage]]:forget()
  end
  if not by_name then
    return tab_sessions
  end
  return vim.iter(tab_sessions):fold({}, function(acc, k, v)
    acc[v] = k
    return acc
  end)
end

---@param reason continuity.DetachReason A reason to pass to detach handlers.
---@param opts continuity.DetachOpts
---@return boolean
local function detach_global(reason, opts)
  if not current_session then
    return false
  end
  assert(sessions[current_session], "Current global session unknown, this is likely a bug"):detach(
    reason,
    opts
  )
  return true
end

--- Detach a tabpage-scoped session, either by its name or tabnr
---@param target (string|continuity.TabNr|(string|continuity.TabNr)[]) Target a tabpage session by name or associated tabpage. Defaults to current tabpage. Also takes a list.
---@param reason continuity.DetachReason A reason to pass to detach handlers.
---@param opts continuity.DetachOpts
---@return boolean
local function detach_tabpage(target, reason, opts)
  if type(target) == "table" then
    local had_effect = false
    vim.iter(target):each(function(v)
      if detach_tabpage(v, reason, opts) then
        had_effect = true
      end
    end)
    return had_effect
  end
  target = target or vim.api.nvim_get_current_tabpage()
  local name, tabnr
  if type(target) == "string" then
    name, tabnr = target, find_tabpage_for_session(target)
  else
    name, tabnr = tab_sessions[target], target
  end
  -- not (tabnr and name) didn't work for emmylua to assert tabnr
  if not tabnr or not name then
    return false
  end
  assert(sessions[name], "Tabpage session not known, this is likely a bug"):detach(reason, opts)
  return true
end

--- Detach all sessions (global + tab-scoped).
---@param reason continuity.DetachReason A reason to pass to detach handlers.
---@param opts continuity.DetachOpts
---@return boolean
local function detach_all(reason, opts)
  local detached_global = detach_global(reason, opts)
  local detached_tabpage =
    detach_tabpage(vim.tbl_keys(list_active_tabpage_sessions()), reason, opts)
  -- Just to make sure everything is reset, this should have been handled by the above logic
  tab_sessions = {}
  local orphaned = {}
  for name, session in pairs(sessions) do
    orphaned[#orphaned + 1] = name
    session:detach(reason, opts)
  end
  sessions = {}
  if not vim.tbl_isempty(orphaned) then
    vim.notify(
      "Found orphaned sessions, this is likely a bug: " .. table.concat(orphaned, ", "),
      vim.log.levels.WARN
    )
    return true
  end
  return detached_global or detached_tabpage
end

--- Detach a session by name.
---@param name string
---@param reason continuity.DetachReason A reason to pass to detach handlers.
---@param opts continuity.DetachOpts
---@return boolean
local function detach_named(name, reason, opts)
  if current_session and current_session == name then
    return detach_global(reason, opts)
  end
  return detach_tabpage(name, reason, opts)
end

--- Save the current global or tabpage state to a named session.
---@param name string The name of the session
---@param opts? continuity.SaveOpts
---@param target_tabpage? continuity.TabNr Instead of saving everything, only save the current tabpage
function save(name, opts, target_tabpage)
  ---@type continuity.SaveOpts
  opts = vim.tbl_extend("keep", opts or {}, {
    notify = true,
    attach = true,
  })
  local session, attached = Session.get(name, opts, target_tabpage)
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
    detach_named(name, "save", { reset = opts.reset })
  end
  if opts.attach then
    session:attach()
  end
end

--- Save the current global state to disk
---@param name string Name of the session
---@param opts? continuity.SaveOpts
function M.save(name, opts)
  save(name, opts)
end

--- Save the state of the current tabpage to disk
---@param name string Name of the tabpage session.
---@param opts? continuity.SaveOpts
function M.save_tab(name, opts)
  save(name, opts, vim.api.nvim_get_current_tabpage())
end

---@param opts? continuity.SaveAllOpts
---@param is_autosave boolean
local function save_all(opts, is_autosave)
  if current_session then
    local session =
      assert(sessions[current_session], "Current global session unknown, this is likely a bug")
    if is_autosave then
      session:autosave(opts)
    else
      session:save(opts)
    end
  end

  -- Difference to Resession:
  -- Resession only saves either the global session or all tabpage-scoped ones.
  -- However, it keeps tabpage-scoped sessions active when a global one is attached with reset=false.
  -- TODO: Improve the handling of simultaneous session types.

  -- Save all tab-scoped sessions
  for _, name in pairs(list_active_tabpage_sessions()) do
    local session = assert(sessions[name], "Tabpage session not known, this is likely a bug")
    if is_autosave then
      session:autosave(opts)
    else
      session:save(opts)
    end
  end
end

--- Trigger an autosave for all attached sessions, respecting session-specific
--- `autosave_enabled` configuration. Mostly for internal use.
---@param opts? continuity.SaveAllOpts
function M.autosave(opts)
  save_all(opts, true)
end

--- Save all currently attached sessions to disk
---@param opts? continuity.SaveAllOpts
function M.save_all(opts)
  save_all(opts, false)
end

--- Load a session
---@param name string The name of the session to load
---@param opts? continuity.LoadOpts Options influencing session load and autosave behavior
---@note The default value of `reset = "auto"` will reset when loading
---      a normal session, but _not_ when loading a tab-scoped session.
function M.load(name, opts)
  opts = vim.tbl_extend("keep", opts or {}, {
    reset = "auto",
    attach = true,
    modified = Config.session.modified,
  })
  ---@cast opts continuity.LoadOpts
  local session_file = util.path.get_session_file(name, opts.dir or Config.session.dir)
  local session = util.path.load_json_file(session_file)
  if not session then
    if not opts.silence_errors then
      error(string.format('Could not find session "%s"', session_file))
    end
    return
  end
  log.fmt_trace("Loading session %s. Data: %s", name, session)
  if opts.reset == "auto" then
    opts.reset = not session.tab_scoped
  end
  if opts.modified == "auto" then
    opts.modified = not not session.modified
  end
  -- If we're going to possibly switch sessions, detach _before_ loading a new session.
  -- This is in contrast to resession, which does this implicitly after loading the new one.
  -- We need to do it eagerly because autosave is baked into the detach logic.
  -- TODO: Consider optionally keeping persistent tab sessions
  if opts.reset then
    -- We're going to close everything, detach both global and all tab scoped sessions.
    detach_all("load", { reset = true, save = opts.detach_save })
    -- Also close all leftovers
    require("continuity.core.layout").close_everything()
  elseif opts.attach and not session.tab_scoped then
    -- Difference to Resession:
    -- If we're loading a new global session, detach a previous one.
    -- This means we're keeping a global session and tabpage-scoped ones at the same time.
    -- Resession always detaches a global session, even when only loading a tabpage-scoped one.
    -- It does not however detach all tabpage-scoped ones when loading a global one without reset.
    -- TODO: Think about implications and the general interplay between global and tab-scoped sessions.
    detach_global("load", { save = opts.detach_save })
  end
  -- Ensure we don't have an existing session named the same as the new one.
  -- TODO: Consider erroring instead? This is somewhat undefined since detaching
  --       after loading the same session's file might have triggered autosave,
  --       but the loaded contents are from before the save.
  --       Seems like implicit, but expected behavior? It might desync modified buffers though.
  detach_named(name, "load", { save = opts.detach_save })
  local state_dir = util.path.get_session_state_dir(name, opts.dir or Config.session.dir)
  local hook_opts =
    vim.tbl_extend("error", opts, { session_file = session_file, state_dir = state_dir })
  Ext.dispatch("pre_load", name, hook_opts --[[@as continuity.LoadHookOpts]])
  Snapshot.restore(session, { reset = opts.reset, state_dir = state_dir, modified = opts.modified })
  if opts.attach then
    Session.new(
      name,
      opts,
      session.tab_scoped and vim.api.nvim_get_current_tabpage() or nil,
      session_file,
      state_dir
    ):attach()
  end
  Ext.dispatch("post_load", name, hook_opts --[[@as continuity.LoadHookOpts]])
end

--- Get the name of the current session
---@return string?
function M.get_current()
  local tabpage = vim.api.nvim_get_current_tabpage()
  return tab_sessions[tabpage] or current_session
end

--- Get data/config remembered from attaching the currently active session
---@return continuity.AttachedSessionInfo?
function M.get_current_data()
  local current = M.get_current()
  if not current then
    return
  end
  local session = assert(sessions[current], "Current session not known, this is likely a bug")
  return session:info()
end

--- Detach from the session that contains the target (or all active sessions if unspecified).
---@param target? ("__global"|"__active"|"__active_tab"|"__all_tabs"|string|integer|(string|integer)[]) The scope/session name/tabnr to detach from. If unspecified, detaches all sessions.
---@param reason? continuity.DetachReason Pass a custom reason to detach handlers. Defaults to `request`.
---@param opts? continuity.DetachOpts
---@return boolean Whether we detached from any session
function M.detach(target, reason, opts)
  reason = reason or "request"
  opts = opts or {}
  if not target then
    return detach_all(reason, opts)
  -- Just hope no one names sessions like this. Alternative: expose M.detach_target = {global = {}, active = {}, ...} as an enum?
  elseif target == "__global" then
    return detach_global(reason, opts)
  elseif target == "__active" then
    return detach_tabpage(nil, reason, opts) or detach_global(reason, opts)
  elseif target == "__active_tab" then
    return detach_tabpage(nil, reason, opts)
  elseif target == "__all_tabs" then
    return detach_tabpage(vim.tbl_keys(list_active_tabpage_sessions()), reason, opts)
  end
  local target_type = type(target)
  if target_type == "string" then
    return detach_named(target, reason, opts)
  elseif target_type == "number" then
    return detach_tabpage(target, reason, opts)
  elseif target_type == "table" then
    -- stylua: ignore
    return vim.iter(target):map(function(v) return M.detach(v, reason, opts) end):any(function(v) return v end)
  end
  log.fmt_error("Invalid detach target: %s", target)
  return false
end

--- List all available saved sessions
---@param opts? resession.ListOpts
---@return string[]
function M.list(opts)
  opts = opts or {}
  local session_dir = util.path.get_session_dir(opts.dir or Config.session.dir)
  if not util.path.exists(session_dir) then
    return {}
  end
  ---@diagnostic disable-next-line: param-type-mismatch, param-type-not-match, unnecessary-assert
  local fd = assert(uv.fs_opendir(session_dir, nil, 256))
  ---@diagnostic disable-next-line: cast-type-mismatch
  ---@cast fd uv.luv_dir_t
  local entries = uv.fs_readdir(fd)
  local ret = {}
  while entries do
    for _, entry in ipairs(entries) do
      if entry.type == "file" then
        local name = entry.name:match("^(.+)%.json$")
        if name then
          ret[#ret + 1] = name
        end
      end
    end
    entries = uv.fs_readdir(fd)
  end
  uv.fs_closedir(fd)
  -- Order options
  if Config.load.order == "filename" then
    -- Sort by filename
    table.sort(ret)
  elseif Config.load.order == "modification_time" then
    -- Sort by modification_time
    local default = { mtime = { sec = 0 } }
    table.sort(ret, function(a, b)
      local file_a = uv.fs_stat(session_dir .. "/" .. a .. ".json") or default
      local file_b = uv.fs_stat(session_dir .. "/" .. b .. ".json") or default
      return file_a.mtime.sec > file_b.mtime.sec
    end)
  elseif Config.load.order == "creation_time" then
    -- Sort by creation_time in descending order (most recent first)
    local default = { birthtime = { sec = 0 } }
    table.sort(ret, function(a, b)
      local file_a = uv.fs_stat(session_dir .. "/" .. a .. ".json") or default
      local file_b = uv.fs_stat(session_dir .. "/" .. b .. ".json") or default
      return file_a.birthtime.sec > file_b.birthtime.sec
    end)
  end
  return ret
end

--- Delete a saved session
---@param name string Name of the session. If not provided, prompt for session to delete
---@param opts? continuity.DeleteOpts
function M.delete(name, opts)
  opts = vim.tbl_extend("keep", opts or {}, {
    notify = true,
  })
  local filename = util.path.get_session_file(name, opts.dir or Config.session.dir)
  if util.path.delete_file(filename) then
    local state_dir = util.path.get_session_state_dir(name, opts.dir or Config.session.dir)
    util.path.rmdir(state_dir, { recursive = true })
    if opts.notify then
      vim.notify(string.format('Deleted session "%s"', name))
    end
  else
    error(string.format('No session "%s"', filename))
  end
  detach_named(name, "delete", { reset = opts.reset })
end

return M

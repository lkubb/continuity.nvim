local Config = require("continuity.config")
local util = require("continuity.util")

local lazy_require = util.lazy_require
local Snapshot = lazy_require("continuity.core.snapshot")
local log = lazy_require("continuity.log")

---@diagnostic disable-next-line: deprecated
local uv = vim.uv or vim.loop

---@class continuity.core.session
local M = {}

local current_session ---@type string?
local tab_sessions = {} ---@type table<continuity.TabNr, string?>
local sessions = {} ---@type table<string, continuity.ActiveSession<continuity.TabTarget>|continuity.ActiveSession<continuity.GlobalTarget>?>

---@param session_file string
---@param silence_errors boolean?
---@return continuity.Snapshot?
local function load_snapshot(session_file, silence_errors)
  local snapshot = util.path.load_json_file(session_file)
  if not snapshot then
    if not silence_errors then
      error(string.format('Could not find session "%s"', session_file))
    end
    return
  end
  return snapshot
end

-- Not sure how assigning Session<T: SessionTarget> is supposed to work with separate definitions.

---@generic T: continuity.SessionTarget
---@type continuity.Session<T> ---@diagnostic disable-line generic-constraint-mismatch
local Session = {} ---@diagnostic disable-line: assign-type-mismatch,missing-fields
---@generic T: continuity.SessionTarget
---@type continuity.PendingSession<T> ---@diagnostic disable-line generic-constraint-mismatch
local PendingSession = {} ---@diagnostic disable-line: assign-type-mismatch,missing-fields
---@generic T: continuity.SessionTarget
---@type continuity.IdleSession<T> ---@diagnostic disable-line generic-constraint-mismatch
local IdleSession = {} ---@diagnostic disable-line: assign-type-mismatch,missing-fields
---@generic T: continuity.SessionTarget
---@type continuity.ActiveSession<T> ---@diagnostic disable-line generic-constraint-mismatch
local ActiveSession = {} ---@diagnostic disable-line: assign-type-mismatch,missing-fields

---@generic T: continuity.SessionTarget
function Session.new(name, session_file, state_dir, opts, tabnr, needs_restore)
  local autosave_enabled = opts.autosave_enabled
  -- "ternary" expression does not work when false is a valid value, need to pre-define for below
  if autosave_enabled == nil then
    autosave_enabled = Config.session.autosave_enabled
  end
  if tabnr == true then
    ---@diagnostic disable-next-line: unnecessary-assert
    assert(needs_restore, "tabnr must not be `true` unless needs_restore is set as well")
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
    tabnr = tabnr ~= true and tabnr or nil,
    tab_scoped = not not tabnr,
    needs_restore = needs_restore,
    _on_attach = {},
    _on_detach = {},
  }
  ---@type continuity.PendingSession<T>|continuity.IdleSession<T>
  local self
  if needs_restore then ---@diagnostic disable-line: unnecessary-if
    self = setmetatable(config, {
      __index = PendingSession,
    })
  else
    self = setmetatable(config, {
      __index = IdleSession,
    })
  end
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

function Session.from_snapshot(name, session_file, state_dir, opts)
  local snapshot = load_snapshot(session_file, opts.silence_errors)
  if not snapshot then
    return
  end
  -- `snapshot.tab_scoped or nil` tripped up emmylua
  if snapshot.tab_scoped then
    return Session.new(name, session_file, state_dir, opts, true, true), snapshot
  end
  return Session.new(name, session_file, state_dir, opts, nil, true), snapshot
end

function Session:add_hook(event, hook)
  local key = "_on_" .. event
  self[key][#self[key] + 1] = hook
  return self
end

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
  return update_autosave
end

function Session:restore(opts, snapshot)
  opts = opts or {}
  snapshot = snapshot or load_snapshot(self.session_file, opts.silence_errors)
  if not snapshot then
    -- The snapshot does not exist, errors were silenced, it might be fine to begin using it
    return self, false
  end
  log.fmt_trace("Loading session %s. Data: %s", self.name, snapshot)
  local load_opts = vim.tbl_extend("keep", self:opts(), opts, { attach = false, reset = "auto" })
  local tabnr = Snapshot.restore_as(self.name, snapshot, load_opts)
  if self.tab_scoped then
    self.tabnr = assert(tabnr, "Restored session defined as tab-scoped, but did not receive tabnr")
  else
    assert(not tabnr, "Restored session defined as global, but received tabnr")
  end
  return self, true
end

function PendingSession:restore(opts, snapshot)
  self.needs_restore = nil
  local self = setmetatable(self, { __index = IdleSession })
  return self:restore(opts, snapshot)
end

function Session:is_attached()
  if not self.tab_scoped then
    return self.name == current_session and sessions[self.name] == self
  end
  ---@cast self continuity.Session<continuity.TabTarget>
  if self.tabnr == true then
    -- Unrestored, cannot be attached
    return false
  end
  return tab_sessions[self.tabnr] == self.name and sessions[self.name] == self
end

function Session:opts()
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
    tab_scoped = self.tab_scoped,
    meta = self.meta,
    session_file = self.session_file,
    state_dir = self.state_dir,
  }
end

function Session:delete(opts)
  opts = opts or {}
  if util.path.delete_file(self.session_file) then
    util.path.rmdir(self.state_dir, { recursive = true })
    if opts.notify ~= false then
      vim.notify(string.format('Deleted session "%s"', self.name))
    end
  elseif not opts.silence_errors then
    error(string.format('No session "%s"', self.session_file))
  end
end

---@generic T: continuity.SessionTarget
function IdleSession:attach()
  self = setmetatable(self, { __index = ActiveSession })
  self._aug = vim.api.nvim_create_augroup("continuity__" .. self.name, { clear = true })
  if self.tab_scoped then
    ---@cast self continuity.ActiveSession<continuity.TabTarget>
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
  ---@cast self continuity.ActiveSession<T>
  sessions[self.name] = self
  for _, hook in ipairs(self._on_attach) do
    hook(self)
  end
  self:_setup_autosave()
  return self
end

function ActiveSession:_setup_autosave()
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

function ActiveSession:attach()
  return self
end

function IdleSession:save(opts, hook_opts)
  local save_opts =
    vim.tbl_extend("keep", self:opts(), hook_opts or {}, { attach = true, reset = false })
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

function ActiveSession:autosave(opts, force)
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

function ActiveSession:detach(reason, opts)
  if self._timer then
    self._timer:stop()
    self._timer = nil
  end
  for _, hook in ipairs(self._on_detach) do
    opts = hook(self, reason, opts) or opts
  end
  -- TODO: Rework save + detach workflow for attached sessions
  if (self.tab_scoped and reason == "tab_closed") or reason == "save" or reason == "delete" then
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
    if self.tab_scoped then
      ---@cast self continuity.ActiveSession<continuity.TabTarget>
      if reason ~= "tab_closed" then
        vim.cmd.tabclose({ self.tabnr, bang = true })
      end
      -- TODO: Consider unloading associated buffers? (cave: should happen even on tab_closed)
    else
      ---@cast self continuity.ActiveSession<continuity.GlobalTarget>
      -- TODO: Everything except tabs with associated sessions?
      require("continuity.core.layout").close_everything()
    end
  end
  if self.tab_scoped then
    ---@cast self continuity.ActiveSession<continuity.TabTarget>
    tab_sessions[self.tabnr] = nil
    self.tabnr = nil
  else
    ---@cast self continuity.ActiveSession<continuity.GlobalTarget>
    current_session = nil
  end
  sessions[self.name] = nil
  return setmetatable(self, IdleSession)
end

function ActiveSession:forget()
  assert(self.tab_scoped, "Cannot forget global session")
  ---@cast self continuity.ActiveSession<continuity.TabTarget>
  if self._aug then ---@diagnostic disable-line: unnecessary-if
    vim.api.nvim_del_augroup_by_id(self._aug)
    self._aug = nil
  end
  sessions[self.name] = nil
  tab_sessions[self.tabnr] = nil
  self.tabnr = nil
  return setmetatable(self, IdleSession)
end

PendingSession = vim.tbl_extend("keep", PendingSession, Session) ---@diagnostic disable-line: assign-type-mismatch
IdleSession = vim.tbl_extend("keep", IdleSession, Session) ---@diagnostic disable-line: assign-type-mismatch
ActiveSession = vim.tbl_extend("keep", ActiveSession, IdleSession) ---@diagnostic disable-line: assign-type-mismatch

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
---@param target? (string|continuity.TabNr|(string|continuity.TabNr)[]) Target a tabpage session by name or associated tabpage. Defaults to current tabpage. Also takes a list.
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
function M.detach_all(reason, opts)
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

---@generic T: continuity.SessionTarget
---@overload fun(name: string, session_file: string, state_dir: string, opts: continuity.LoadOpts|continuity.SaveOpts): continuity.IdleSession<continuity.GlobalTarget>
---@overload fun(name: string, session_file: string, state_dir: string, opts: continuity.LoadOpts|continuity.SaveOpts, tabnr: nil): continuity.IdleSession<continuity.GlobalTarget>
---@overload fun(name: string, session_file: string, state_dir: string, opts: continuity.LoadOpts|continuity.SaveOpts, tabnr: continuity.TabNr): continuity.IdleSession<continuity.TabTarget>
---@param name string
---@param session_file string
---@param state_dir string
---@param opts continuity.LoadOpts|continuity.SaveOpts
---@param tabnr continuity.TabNr?
---@return continuity.IdleSession<T>
function M.create_new(name, session_file, state_dir, opts, tabnr)
  -- help emmylua resolve to the proper type with this conditional
  if tabnr then
    return Session.new(name, session_file, state_dir, opts, tabnr)
  end
  return Session.new(name, session_file, state_dir, opts)
end

---@generic T: continuity.SessionTarget
---@param name string
---@param session_file string
---@param state_dir string
---@param opts continuity.LoadOpts
---@return continuity.PendingSession<T>?
---@return continuity.Snapshot?
function M.from_snapshot(name, session_file, state_dir, opts)
  return Session.from_snapshot(name, session_file, state_dir, opts)
end

---@generic T: continuity.SessionTarget
---@return continuity.ActiveSession<T>[]
function M.get_all()
  local global = M.get_global()
  ---@type continuity.ActiveSession<T>[]
  local res = global and { global } or {}
  return vim.list_extend(res, vim.tbl_values(M.get_tabs()))
end

---@return table<continuity.TabNr, continuity.ActiveSession<continuity.TabTarget>>
function M.get_tabs()
  return vim.iter(pairs(list_active_tabpage_sessions())):fold({}, function(res, tabnr, name)
    res[tabnr] = assert(
      sessions[name] and sessions[name].tabnr == tabnr,
      "Tabpage session not known or points to wrong tab, this is likely a bug"
    )
    return res
  end)
end

---@generic T: continuity.SessionTarget
---@param name string The session name to get
---@return continuity.ActiveSession<T>?
function M.get_named(name)
  return sessions[name]
end

---@param tabnr? continuity.TabNr The tabnr the session is associated with. Empty for current tab.
---@return continuity.ActiveSession<continuity.TabTarget>?
function M.get_tabnr(tabnr)
  ---@type string?
  local name = list_active_tabpage_sessions()[tabnr or vim.api.nvim_get_current_tabpage()]
  ---@diagnostic disable-next-line: return-type-mismatch
  return name
      and assert(
        sessions[name] and sessions[name].tabnr == tabnr,
        "Tabpage session not known or points to wrong tab, this is likely a bug"
      )
      and sessions[name]
    or nil
end

---@return continuity.ActiveSession<continuity.GlobalTarget>?
function M.get_global()
  ---@diagnostic disable-next-line: return-type-mismatch
  return current_session
      and assert(
        sessions[current_session] and sessions[current_session].tabnr == nil,
        "Current global session unknown or points to tab, this is likely a bug"
      )
      and sessions[current_session]
    or nil
end

---@generic T: continuity.SessionTarget
---@return continuity.ActiveSession<T>?
function M.get_active()
  local name = M.get_current()
  return name and assert(sessions[name], "Current session not known, this is likely a bug") or nil
end

---@param opts? continuity.SaveAllOpts
---@param is_autosave boolean
local function save_all(opts, is_autosave)
  -- Difference to Resession:
  -- Resession only saves either the global session or all tabpage-scoped ones.
  -- However, it keeps tabpage-scoped sessions active when a global one is attached with reset=false.
  -- TODO: Improve the handling of simultaneous session types.
  for _, session in ipairs(M.get_all()) do
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

--- Get the name of the current session
---@return string?
function M.get_current()
  local tabpage = vim.api.nvim_get_current_tabpage()
  return tab_sessions[tabpage] or current_session
end

--- Get data/config remembered from attaching the currently active session
---@return continuity.ActiveSessionInfo?
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
    return M.detach_all(reason, opts)
  -- Just assume no one names sessions like this. Alternative: expose M.detach_target = {global = {}, active = {}, ...} as an enum?
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

return M

local Config = require("finni.config")
local util = require("finni.util")

local lazy_require = util.lazy_require
local Snapshot = lazy_require("finni.core.snapshot")
local log = lazy_require("finni.log")

---@diagnostic disable-next-line: deprecated
local uv = vim.uv or vim.loop

---@class finni.core.session
local M = {}

---@namespace finni.core

local current_session ---@type string?
local tab_sessions = {} ---@type table<TabID, string?>
local sessions = {} ---@type table<string, ActiveSession<Session.TabTarget>|ActiveSession<Session.GlobalTarget>?>

---@param session_file string
---@param silence_errors? boolean
---@return Snapshot?
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

---@generic T: Session.Target
---@type Session<T> ---@diagnostic disable-line generic-constraint-mismatch
local Session = {} ---@diagnostic disable-line: assign-type-mismatch,missing-fields
---@generic T: Session.Target
---@type PendingSession<T> ---@diagnostic disable-line generic-constraint-mismatch
local PendingSession = {} ---@diagnostic disable-line: assign-type-mismatch,missing-fields
---@generic T: Session.Target
---@type IdleSession<T> ---@diagnostic disable-line generic-constraint-mismatch
local IdleSession = {} ---@diagnostic disable-line: assign-type-mismatch,missing-fields
---@generic T: Session.Target
---@type ActiveSession<T> ---@diagnostic disable-line generic-constraint-mismatch
local ActiveSession = {} ---@diagnostic disable-line: assign-type-mismatch,missing-fields

---@generic T: Session.Target
function Session.new(name, session_file, state_dir, context_dir, opts, tabid, needs_restore)
  if tabid == true then
    ---@diagnostic disable-next-line: unnecessary-assert
    assert(needs_restore, "tabid must not be `true` unless needs_restore is set as well")
  end
  ---@type Session.Config
  local config = {
    -- Session.Config native part
    session_file = session_file,
    state_dir = state_dir,
    context_dir = context_dir,
    -- We need to query defaults for these values during load since we cannot
    -- dynamically reconfigure them easily
    autosave_enabled = util.opts.coalesce("autosave_enabled", false, opts, Config.session), ---@diagnostic disable-line: assign-type-mismatch
    autosave_interval = opts.autosave_interval or Config.session.autosave_interval,
    autosave_notify = opts.autosave_notify,
    meta = opts.meta,
    -- snapshot.CreateOpts part
    modified = opts.modified,
    -- These can be defined even when loading to be able to configure autosave settings.
    -- They currently don't affect loading though.
    options = opts.options,
    buf_filter = opts.buf_filter,
    tab_buf_filter = opts.tab_buf_filter,
    changelist = opts.changelist,
    jumps = opts.jumps,
    global_marks = opts.global_marks,
    local_marks = opts.local_marks,
    command_history = opts.command_history,
    search_history = opts.search_history,
    input_history = opts.input_history,
    expr_history = opts.expr_history,
    debug_history = opts.debug_history,
    -- internals
    name = name,
    tabid = tabid ~= true and tabid or nil,
    tab_scoped = not not tabid,
    needs_restore = needs_restore,
    _on_attach = {},
    _on_detach = {},
  }
  ---@type PendingSession<T>|IdleSession<T>
  local self
  if needs_restore then ---@diagnostic disable-line: unnecessary-if
    self = setmetatable(config --[[@as table]], {
      __index = PendingSession,
    })
  else
    self = setmetatable(config --[[@as table]], {
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

function Session.from_snapshot(name, session_file, state_dir, context_dir, opts)
  local snapshot = load_snapshot(session_file, opts.silence_errors)
  if not snapshot then
    return
  end
  ---@type Session.InitOptsWithMeta
  local session_opts = {
    autosave_enabled = opts.autosave_enabled,
    autosave_interval = opts.autosave_interval,
    autosave_notify = opts.autosave_notify,
    on_attach = opts.on_attach,
    on_detach = opts.on_detach,
    buf_filter = opts.buf_filter,
    modified = opts.modified,
    options = opts.options,
    tab_buf_filter = opts.tab_buf_filter,
    meta = opts.meta,
    changelist = opts.changelist,
    jumps = opts.jumps,
    global_marks = opts.global_marks,
    local_marks = opts.local_marks,
    command_history = opts.command_history,
    search_history = opts.search_history,
    input_history = opts.input_history,
    expr_history = opts.expr_history,
    debug_history = opts.debug_history,
  }
  -- `snapshot.tab_scoped or nil` tripped up emmylua
  if snapshot.tab_scoped then
    return Session.new(name, session_file, state_dir, context_dir, session_opts, true, true),
      snapshot
  end
  return Session.new(name, session_file, state_dir, context_dir, session_opts, nil, true), snapshot
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
      "changelist",
      "jumps",
      "global_marks",
      "local_marks",
      "history",
      "command_history",
      "search_history",
      "input_history",
      "expr_history",
      "debug_history",
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
  log.trace("Loading session %s. Data: %s", self.name, snapshot)
  local load_opts =
    vim.tbl_extend("keep", self:opts() --[[@as table]], opts, { attach = false, reset = "auto" })
  local tabid = Snapshot.restore_as(self.name, snapshot, load_opts)
  if self.tab_scoped then
    self.tabid = assert(tabid, "Restored session defined as tab-scoped, but did not receive tabid")
  else
    assert(not tabid, "Restored session defined as global, but received tabid")
  end
  return self, true
end

function PendingSession:restore(opts, snapshot)
  self.needs_restore = nil
  local self_idle = setmetatable(self, { __index = IdleSession })
  return self_idle:restore(opts, snapshot)
end

function Session:is_attached()
  if not self.tab_scoped then
    return self.name == current_session and sessions[self.name] == self
  end
  ---@cast self Session<Session.TabTarget>
  if self.tabid == true then
    -- Unrestored, cannot be attached
    return false
  end
  return tab_sessions[self.tabid] == self.name and sessions[self.name] == self
end

function Session:opts()
  return {
    -- Snapshot options
    modified = self.modified,
    options = self.options,
    buf_filter = self.buf_filter,
    tab_buf_filter = self.tab_buf_filter,
    changelist = self.changelist,
    jumps = self.jumps,
    global_marks = self.global_marks,
    local_marks = self.local_marks,
    command_history = self.command_history,
    search_history = self.search_history,
    input_history = self.input_history,
    expr_history = self.expr_history,
    debug_history = self.debug_history,
    -- Information for hooks
    --   1. Session handling info
    autosave_enabled = self.autosave_enabled,
    autosave_interval = self.autosave_interval,
    autosave_notify = self.autosave_notify,
    --   2. Metadata
    meta = self.meta,
    session_file = self.session_file,
    state_dir = self.state_dir,
    context_dir = self.context_dir,
  }
end

function Session:info()
  return {
    -- Snapshot options
    modified = self.modified,
    options = self.options,
    buf_filter = self.buf_filter,
    tab_buf_filter = self.tab_buf_filter,
    changelist = self.changelist,
    jumps = self.jumps,
    global_marks = self.global_marks,
    local_marks = self.local_marks,
    command_history = self.command_history,
    search_history = self.search_history,
    input_history = self.input_history,
    expr_history = self.expr_history,
    debug_history = self.debug_history,
    -- Session handling
    autosave_enabled = self.autosave_enabled,
    autosave_interval = self.autosave_interval,
    autosave_notify = self.autosave_notify,
    -- Metadata
    name = self.name,
    tabid = self.tabid,
    tab_scoped = self.tab_scoped,
    meta = self.meta,
    session_file = self.session_file,
    state_dir = self.state_dir,
    context_dir = self.context_dir,
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

---@generic T: Session.Target
function IdleSession:attach()
  self = setmetatable(self, { __index = ActiveSession })
  self._aug = vim.api.nvim_create_augroup("finni__" .. self.name, { clear = true })
  if self.tab_scoped then
    ---@cast self ActiveSession<Session.TabTarget>
    tab_sessions[self.tabid] = self.name
    vim.api.nvim_create_autocmd("TabClosed", {
      pattern = tostring(self.tabid),
      callback = function()
        self:detach("tab_closed", {})
      end,
      once = true,
      group = self._aug,
    })
  else
    current_session = self.name
  end
  ---@cast self ActiveSession<T>
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

function IdleSession:save(opts)
  ---@type Session.KnownHookOpts.SideEffects
  local default_hook_opts = { attach = true, reset = false }
  ---@diagnostic disable-next-line: assign-type-mismatch
  ---@type Session.Init.Paths & Session.Init.Autosave & Session.Init.Meta & snapshot.CreateOpts & Session.KnownHookOpts & PassthroughOpts
  local save_opts = vim.tbl_extend(
    "keep",
    self:opts() --[[@as table]],
    opts --[[@as table]]
      or {},
    default_hook_opts --[[@as table]]
  )
  if
    not Snapshot.save_as(
      self.name,
      save_opts,
      self.tabid,
      save_opts.session_file,
      save_opts.state_dir,
      save_opts.context_dir
    )
  then
    return false
  end
  if save_opts.notify ~= false then
    vim.notify(string.format('Saved session "%s"', self.name))
  end
  return true
end

function ActiveSession:autosave(opts, force)
  if not (force or self.autosave_enabled) then
    return
  end
  opts = opts or {}
  local notify = util.opts.coalesce(
    "autosave_notify",
    true,
    { autosave_notify = opts.notify },
    opts,
    self,
    Config.session
  )
  local save_opts = vim.tbl_extend("keep", { notify = notify }, opts)
  self:save(save_opts)
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
      ---@cast self ActiveSession<Session.TabTarget>
      if reason ~= "tab_closed" then
        vim.cmd.tabclose({ self.tabid, bang = true })
      end
      -- TODO: Consider unloading associated buffers? (cave: should happen even on tab_closed)
    else
      ---@cast self ActiveSession<Session.GlobalTarget>
      -- TODO: Everything except tabs with associated sessions?
      require("finni.core.layout").close_everything()
    end
  end
  if self.tab_scoped then
    ---@cast self ActiveSession<Session.TabTarget>
    tab_sessions[self.tabid] = nil
    self.tabid = nil
  else
    ---@cast self ActiveSession<Session.GlobalTarget>
    current_session = nil
  end
  sessions[self.name] = nil
  return setmetatable(self, { __index = IdleSession })
end

function ActiveSession:forget()
  assert(self.tab_scoped, "Cannot forget global session")
  ---@cast self ActiveSession<Session.TabTarget>
  if self._aug then ---@diagnostic disable-line: unnecessary-if
    vim.api.nvim_del_augroup_by_id(self._aug)
    self._aug = nil
  end
  sessions[self.name] = nil
  tab_sessions[self.tabid] = nil
  self.tabid = nil
  return setmetatable(self, { __index = IdleSession })
end

PendingSession = vim.tbl_extend("keep", PendingSession, Session) ---@diagnostic disable-line: assign-type-mismatch
IdleSession = vim.tbl_extend("keep", IdleSession, Session) ---@diagnostic disable-line: assign-type-mismatch
ActiveSession = vim.tbl_extend("keep", ActiveSession, IdleSession) ---@diagnostic disable-line: assign-type-mismatch

---@param name string
---@return TabID?
local function find_tabpage_for_session(name)
  for k, v in pairs(tab_sessions) do
    if v == name then
      return k
    end
  end
end

---@overload fun(by_name: true): table<string,TabID?>
---@overload fun(by_name: false?): table<TabID,string?>
---@param by_name? boolean Index returned mapping by session name instead of tab number
---@return table<string,TabID?>|table<TabID,string?> active_tab_sessions #
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

---@param reason Session.DetachReason Reason to pass to detach handlers.
---@param opts Session.DetachOpts & PassthroughOpts
---@return boolean detached Whether we detached from any session
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

--- Detach a tabpage-scoped session, either by its name or tabid
---@param target? (string|TabID|(string|TabID)[]) #
---   Target a tabpage session by name or associated tabpage.
---   Defaults to current tabpage. Also takes a list.
---@param reason Session.DetachReason Reason to pass to detach handlers.
---@param opts Session.DetachOpts & PassthroughOpts
---@return boolean detached Whether we detached from any session
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
  local name, tabid
  if type(target) == "string" then
    name, tabid = target, find_tabpage_for_session(target)
  else
    name, tabid = tab_sessions[target], target
  end
  -- not (tabid and name) didn't work for emmylua to assert tabid
  if not tabid or not name then
    return false
  end
  assert(sessions[name], "Tabpage session not known, this is likely a bug"):detach(reason, opts)
  return true
end

--- Detach all sessions (global + tab-scoped).
---@param reason Session.DetachReason Reason to pass to detach handlers.
---@param opts Session.DetachOpts & PassthroughOpts
---@return boolean detached Whether we detached from any session
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
---@param name string Name of the session to detach
---@param reason Session.DetachReason Reason to pass to detach handlers.
---@param opts Session.DetachOpts & PassthroughOpts
---@return boolean detached Whether we detached from any session
local function detach_named(name, reason, opts)
  if current_session and current_session == name then
    return detach_global(reason, opts)
  end
  return detach_tabpage(name, reason, opts)
end

---@generic T: Session.Target
---@overload fun(name: string, session_file: string, state_dir: string, context_dir: string, opts: Session.InitOptsWithMeta): IdleSession<Session.GlobalTarget>
---@overload fun(name: string, session_file: string, state_dir: string, context_dir: string, opts: Session.InitOptsWithMeta, tabid: nil): IdleSession<Session.GlobalTarget>
---@overload fun(name: string, session_file: string, state_dir: string, context_dir: string, opts: Session.InitOptsWithMeta, tabid: TabID): IdleSession<Session.TabTarget>
---@param name string
---@param session_file string
---@param state_dir string
---@param context_dir string
---@param opts Session.InitOptsWithMeta
---@param tabid? TabID
---@return IdleSession<T>
function M.create_new(name, session_file, state_dir, context_dir, opts, tabid)
  -- help emmylua resolve to the proper type with this conditional
  if tabid then
    return Session.new(name, session_file, state_dir, context_dir, opts, tabid)
  end
  return Session.new(name, session_file, state_dir, context_dir, opts)
end

---@generic T: Session.Target
---@param name string
---@param session_file string
---@param state_dir string
---@param context_dir string
---@param opts Session.InitOptsWithMeta & finni.SideEffects.SilenceErrors
---@return PendingSession<T>?
---@return Snapshot?
function M.from_snapshot(name, session_file, state_dir, context_dir, opts)
  return Session.from_snapshot(name, session_file, state_dir, context_dir, opts)
end

---@generic T: Session.Target
---@return ActiveSession<T>[]
function M.get_all()
  local global = M.get_global()
  ---@type ActiveSession<T>[]
  local res = global and { global } or {}
  return vim.list_extend(res, vim.tbl_values(M.get_tabs()))
end

---@return table<TabID, ActiveSession<Session.TabTarget>>
function M.get_tabs()
  return vim.iter(pairs(list_active_tabpage_sessions())):fold({}, function(res, tabid, name)
    res[tabid] = assert(
      sessions[name] and sessions[name].tabid == tabid,
      "Tabpage session not known or points to wrong tab, this is likely a bug"
    )
    return res
  end)
end

---@generic T: Session.Target
---@param name string The session name to get
---@return ActiveSession<T>?
function M.get_named(name)
  return sessions[name]
end

---@param tabid? TabID #
---    Tab number the session is associated with. Empty for current tab.
---@return ActiveSession<Session.TabTarget>?
function M.get_tabid(tabid)
  ---@type string?
  local name = list_active_tabpage_sessions()[tabid or vim.api.nvim_get_current_tabpage()]
  ---@diagnostic disable-next-line: return-type-mismatch
  return name
      and assert(
        sessions[name] and sessions[name].tabid == tabid,
        "Tabpage session not known or points to wrong tab, this is likely a bug"
      )
      and sessions[name]
    or nil
end

---@return ActiveSession<Session.GlobalTarget>? global_session #
function M.get_global()
  return current_session
      and assert(
        sessions[current_session] and sessions[current_session].tabid == nil,
        "Current global session unknown or points to tab, this is likely a bug"
      )
      and sessions[current_session] --[[@as ActiveSession<Session.GlobalTarget>]]
    or nil
end

---@generic T: Session.Target
---@return ActiveSession<T>? active_session #
function M.get_active()
  local name = M.get_current()
  return name and assert(sessions[name], "Current session not known, this is likely a bug") or nil
end

---@param opts? Session.AutosaveOpts & PassthroughOpts
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
---@param opts? Session.AutosaveOpts & PassthroughOpts
function M.autosave(opts)
  save_all(opts, true)
end

--- Save all currently attached sessions to disk
---@param opts? Session.AutosaveOpts & PassthroughOpts
function M.save_all(opts)
  save_all(opts, false)
end

--- Get the name of the current session
---@return string? current_name #
function M.get_current()
  local tabpage = vim.api.nvim_get_current_tabpage()
  return tab_sessions[tabpage] or current_session
end

--- Get data/config remembered from attaching the currently active session
---@return ActiveSessionInfo? info #
function M.get_current_data()
  local current = M.get_current()
  if not current then
    return
  end
  local session = assert(sessions[current], "Current session not known, this is likely a bug")
  return session:info()
end

--- Detach from the session that contains the target (or all active sessions if unspecified).
---@param target? ("__global"|"__active"|"__active_tab"|"__all_tabs"|string|integer|(string|integer)[]) #
---   The scope/session name/tabid to detach from. If unspecified, detaches all sessions.
---@param reason? Session.DetachReason #
---   Pass a custom reason to detach handlers. Defaults to `request`.
---@param opts? Session.DetachOpts & PassthroughOpts
---@return boolean detached Whether we detached from any session
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
  log.error("Invalid detach target: %s", target)
  return false
end

local autosave_group
function M.setup()
  autosave_group = vim.api.nvim_create_augroup("FinniAutosave", { clear = true })
  -- TODO: Optionally (?) use ExitPre instead to be able to skip unsaved changes dialog when modified=true?
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = autosave_group,
    callback = function()
      -- Trigger detach, which in turn triggers autosave for sessions that have it enabled.
      M.detach(nil, "quit")
    end,
  })
end

return M

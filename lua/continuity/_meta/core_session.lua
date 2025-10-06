---@meta
---@namespace continuity.core

---@class Session.Init.Paths
---@field session_file string The path to the session file
---@field state_dir string The path to the directory holding session-associated data

---@class Session.Init.Autosave
---@field autosave_enabled? boolean When this session is attached, automatically save it in intervals. Defaults to false.
---@field autosave_interval? integer Seconds between autosaves of this session, if enabled. Defaults to 60.
---@field autosave_notify? boolean Trigger a notification when autosaving this session. Defaults to true.

--- Autosave configuration after initializing the session, needs to resolve actual values.
---@class Session.Init.Autosave.Rendered: Session.Init.Autosave
---@field autosave_enabled boolean When this session is attached, automatically save it in intervals. Defaults to false.
---@field autosave_interval integer Seconds between autosaves of this session, if enabled. Defaults to 60.

---@class Session.Init.Hooks
---@field on_attach? Session.AttachHook A function that's called when attaching to this session. No global default.
---@field on_detach? Session.DetachHook A function that's called when detaching from this session. No global default.

---@class Session.Init.Meta
---@field meta? table External data remembered in association with this session. Useful to build on top of the core API.

--- Options to influence how an attached session is handled.
---@alias Session.InitOpts Session.Init.Autosave & Session.Init.Hooks & snapshot.CreateOpts
--- Options to influence how an attached session is handled plus `meta` field, which can only be populated by passing
--- it to the session constructor and is useful for custom session handling.
---@alias Session.InitOptsWithMeta Session.InitOpts & Session.Init.Meta

--- Session-associated configuration, rendered from passed options and default config.
---@alias Session.Config Session.Init.Paths & Session.Init.Autosave.Rendered & Session.Init.Hooks & Session.Init.Meta & snapshot.CreateOpts

--- Compatibility with resession-style hooks from the `continuity.session` API
---@alias Session.KnownHookOpts.Dir continuity.session.DirParam

--- Tell hooks about what happens next. This is the only form that's supported in `core.session`. `reset` being `auto` should be handled before.
---@alias Session.KnownHookOpts.SideEffects continuity.SideEffects.Attach & continuity.SideEffects.Reset

--- All internally known hook params that should be passed to pre/post save/load hooks if possible.
---@alias Session.KnownHookOpts Session.KnownHookOpts.Dir & Session.KnownHookOpts.SideEffects

--- Options for saving attached sessions with the config that was passed in when loading them
---@alias Session.AutosaveOpts continuity.SideEffects.Notify

--- Options for detaching sessions
---@alias Session.DetachOpts continuity.SideEffects.Reset & continuity.SideEffects.Save

--- Detach reasons are passed to avoid unintended side effects during operations. They are passed to
--- detach hooks as well. These are the ones built in to the core session handling.
---@alias Session.DetachReasonBuiltin "delete"|"load"|"quit"|"request"|"save"|"tab_closed"

--- Custom detach reasons can be given as well.
---@alias Session.DetachReason Session.DetachReasonBuiltin|string

--- Options for basic snapshot restoration (different from session loading!).
--- Note that `reset` here does not handle detaching other active sessions,
--- it really resets everything if set to true. If set to false, opens a new tab.
--- Handle with care!
---@alias Session.RestoreOpts continuity.SideEffects.Reset & continuity.SideEffects.SilenceErrors

--- Attach hooks can inspect the session.
--- Modifying it in-place should work, but it's not officially supported.
---@alias Session.AttachHook fun(session: IdleSession)

--- Detach hooks can modify detach opts in place or return new ones.
--- They can inspect the session. Modifying it in-place should work, but it's not officially supported.
---@alias Session.DetachHook fun(session: ActiveSession, reason: Session.DetachReason, opts: Session.DetachOpts & PassthroughOpts): (Session.DetachOpts & PassthroughOpts)?

--- Represents the complete internal state of a session
---@class ActiveSessionInfo: Session.Config
---@field name string The name of the session
---@field tabnr (TabNr|true)? The tab the session is attached to, if any. Can be `true`, which indicates it's a tab-scoped session that has not been restored yet - although not when requesting via the API
---@field tab_scoped boolean Whether the session is tab-scoped

-- The following type definitions are quite painful at the moment. I'm unsure how to type this
-- properly/whether emmylua just misses the functionality.
-- Specifically, the :attach() and :restore() methods caused a lot of headaches.

---------------------------------------------------------------------------------------------------
-- 0. Common session data/behavior
---------------------------------------------------------------------------------------------------

--- The associated session is tab-scoped to this specific tab
---@class Session.TabTarget
---@field tab_scoped true
---@field tabnr TabNr

--- The associated session is global-scoped
---@class Session.GlobalTarget
---@field tab_scoped false
---@field tabnr nil

---@alias Session.Target Session.TabTarget|Session.GlobalTarget

--- Common session behavior.
---@class Session<T: Session.Target>: T, Session.Config
---@field name string
---@field tab_scoped boolean
---@field tabnr TabNr?
---@field _on_attach Session.AttachHook[]
---@field _on_detach Session.DetachHook[]
local Session = {}

--- Create a new session object. `needs_restore` indicates that the
--- snapshot was loaded from a file and has not yet been restored into neovim.
---@param name string
---@param session_file string
---@param state_dir string
---@param opts Session.InitOptsWithMeta
---@return IdleSession<Session.GlobalTarget>
function Session.new(name, session_file, state_dir, opts) end
---@param name string
---@param session_file string
---@param state_dir string
---@param opts Session.InitOptsWithMeta
---@param tabnr TabNr
---@return IdleSession<Session.TabTarget>
function Session.new(name, session_file, state_dir, opts, tabnr) end
---@param name string
---@param session_file string
---@param state_dir string
---@param opts Session.InitOptsWithMeta
---@param tabnr nil
---@param needs_restore true
---@return PendingSession<Session.GlobalTarget>
function Session.new(name, session_file, state_dir, opts, tabnr, needs_restore) end
---@param name string
---@param session_file string
---@param state_dir string
---@param opts Session.InitOptsWithMeta
---@param tabnr true
---@param needs_restore true
---@return PendingSession<Session.TabTarget>
function Session.new(name, session_file, state_dir, opts, tabnr, needs_restore) end

--- Create a new session by loading a snapshot, which you need to restore explicitly.
---@param name string
---@param session_file string
---@param state_dir string
---@param opts Session.InitOptsWithMeta & continuity.SideEffects.SilenceErrors
---@return PendingSession<T>? loaded_session The session object, if it could be loaded
---@return Snapshot? snapshot The snapshot data, if it could be loaded
function Session.from_snapshot(name, session_file, state_dir, opts) end

--- Add hooks to attach/detach events for this session.
---@param event "attach"
---@param hook Session.AttachHook
---@return self
function Session:add_hook(event, hook) end
---@param event "detach"
---@param hook Session.DetachHook
---@return self
function Session:add_hook(event, hook) end

--- Update modifiable options without attaching/detaching a session
---@param opts Session.InitOptsWithMeta
---@return boolean modified
function Session:update(opts) end

--- Restore a snapshot from disk or memory
---@param opts? Session.RestoreOpts & PassthroughOpts
---@param snapshot? Snapshot Snapshot to restore. If unspecified, loads from file.
---@return IdleSession<T> self The object itself, but now attachable
---@return boolean success Whether restoration was successful. Only sensible when `silence_errors` is true.
function Session:restore(opts, snapshot) end

--- Check whether this session is attached correctly.
--- Note: It must be the same instance that `:attach()` was called on, not a copy.
---@return TypeGuard<ActiveSession<T>>
function Session:is_attached() end -- I couldn't make TypeGuard<ActiveSession<T>> work properly with method syntax

--- Turn the session object into opts for snapshot restore/save operations
---@return Session.Init.Paths & Session.Init.Autosave & Session.Init.Meta & snapshot.CreateOpts
function Session:opts() end

--- Get information about this session
---@return ActiveSessionInfo
function Session:info() end

--- Delete a saved session
---@param opts? continuity.SideEffects.Notify & continuity.SideEffects.SilenceErrors
function Session:delete(opts) end

---------------------------------------------------------------------------------------------------
-- 1. Unrestored session, loaded from disk. Needs to be `:restore()`d before we can work with it.
---------------------------------------------------------------------------------------------------

--- Represents a session that has been loaded from a snapshot and needs
--- to be applied still before being able to attach it.
---@class PendingSession<T: Session.Target>: Session<T>
---@field needs_restore true
local PendingSession = {}

---------------------------------------------------------------------------------------------------
-- 2. Unattached session, either restored from disk or freshly created.
---------------------------------------------------------------------------------------------------

--- A general session config that can be attached, turning it into an active session.
---@class IdleSession<T: Session.Target>: Session<T>
local IdleSession = {}

--- Attach this session. If it was loaded from a snapshot file, you must ensure you restore
--- the snapshot (`:restore()`) before calling this method.
--- It's fine to attach an already attached session.
---@return ActiveSession<T>
function IdleSession:attach() end

--- Save this session following its configured configuration.
--- Note: Any save configuration must be applied via `Session.update(opts)` before
--- callig this method since all session-specific options that might be contained
--- in `opts` are overridded with ones configured for the session.
---@param opts? Session.AutosaveOpts & Session.KnownHookOpts & PassthroughOpts Success notification setting plus options that need to be passed through to pre_save/post_save hooks.
---@return boolean success
function IdleSession:save(opts) end

---------------------------------------------------------------------------------------------------
-- 3. Attached session allow autosave and detaching
---------------------------------------------------------------------------------------------------

--- An active (attached) session.
---@class ActiveSession<T: Session.Target>: IdleSession<T>
---@field autosave_enabled boolean Autosave this attached session in intervals and when detaching
---@field autosave_interval integer Seconds between autosaves of this session, if enabled.
---@field _aug integer Neovim augroup for this session
---@field _timer uv.uv_timer_t? Autosave timer, if enabled
---@field private _setup_autosave fun(self: ActiveSession<T>): nil
local ActiveSession = {}

---@param opts? Session.AutosaveOpts & PassthroughOpts
---@param force? boolean
function ActiveSession:autosave(opts, force) end

--- Detach from this session. Ensure the session is attached before trying to detach,
--- otherwise you'll receive an error.
--- Hint: If you are sure the session should be attached, but still receive an error,
--- ensure that you call `detach()` on the specific session instance you called `:attach()` on before, not a copy.
----@param self ActiveSession<T>
---@param reason Session.DetachReason A reason for detaching, also passed to detach hooks. Only inbuilt reasons influence behavior by default.
---@param opts Session.DetachOpts & PassthroughOpts Influence side effects. `reset` removes all associated resources. `save` overrides autosave behavior.
---@return IdleSession<T>
function ActiveSession:detach(reason, opts) end
-- Note: In unions of e.g. ActiveSession<Session.TabTarget>|ActiveSession<Session.GlobalTarget>, the return type is wrongly
-- inferred as IdleSession<Session.TabTarget> by emmylua here ^.

--- Mark a **tab** session as invalid (i.e. remembered as attached, but its tab is gone).
--- Removes associated resources, skips autosave.
---@param self ActiveSession<Session.TabTarget>
---@return IdleSession<Session.TabTarget>
function ActiveSession.forget(self) end

--- Restore a snapshot from disk or memory
--- It seems emmylua does not pick up this override and infers IdleSession<T> instead.
---@param opts? Session.RestoreOpts & PassthroughOpts
---@param snapshot? Snapshot Snapshot to restore. If unspecified, loads from file.
---@return ActiveSession<T> self The object itself
---@return boolean success Whether restoration was successful. Only sensible when `silence_errors` is true.
function ActiveSession:restore(opts, snapshot) end

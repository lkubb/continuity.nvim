---@meta

--- API options for `core.list`
---@class (exact) resession.ListOpts
---@field dir? string Name of directory to list (overrides config.dir)

---@class (exact) resession.DeleteOpts
---@field dir? string Name of directory to delete from (overrides config.dir)
---@field notify? boolean Notify on success (default true)

--- API options for `core.delete`
---@class continuity.DeleteOpts: resession.DeleteOpts
---@field reset? boolean When deleting an attached session, close all associated tabpages. Defaults to false.
---@field silence_errors? boolean Don't error when trying to delete a non-existent session

--- API options for `core.save`
---@class continuity.SaveOpts: continuity.SessionOpts
---@field attach? boolean Stay attached to session after saving (default true)
---@field dir? string Name of directory to save to (overrides config.dir)
---@field meta? table External data remembered in association with this session. Useful to build on top of the core API.
---@field notify? boolean Notify on success (default true)
---@field reset? boolean When not staying attached to the session, close all associated tabpages. Defaults to false.

--- API options for `core.save_all`
---@class continuity.SaveAllOpts
---@field notify? boolean Notify on success

--- API options for `core.load`
---@class continuity.LoadOpts: continuity.SessionOpts
---@field attach? boolean Attach to session after loading
---@field dir? string Name of directory to load from (overrides config.dir)
---@field meta? table External data remembered in association with this session. Useful to build on top of the core API.
---@field reset? boolean|"auto" Close everything before loading the session (default "auto")
---@field silence_errors? boolean Don't error when trying to load a missing session
---@field detach_save? boolean When detaching other sessions, override their autosave behavior

--- API options for `core.detach`
---@class continuity.DetachOpts
---@field reset? boolean Whether to close all session-associated tabpages. Defaults to false.
---@field save? boolean Whether to save the session before detaching

---@alias continuity.DetachReasonBuiltin "delete"|"load"|"quit"|"request"|"save"|"tab_closed"
---@alias continuity.DetachReason continuity.DetachReasonBuiltin|string

---@class (exact) resession.Extension.OnSaveOpts
---@field tabpage integer? The tabpage being saved, if in a tab-scoped session

---@class (exact) resession.Extension
---@field on_save? fun(opts: resession.Extension.OnSaveOpts): any
---@field on_pre_load? fun(data: any)
---@field on_post_load? fun(data: any)
---@field config? fun(options: table)
---@field is_win_supported? fun(winid: integer, bufnr: integer): boolean
---@field save_win? fun(winid: integer): any
---@field load_win? fun(winid: integer, data: any): integer?

---@class continuity.Extension: resession.Extension
---@field on_post_bufinit? fun(data: any, visible_only: boolean)
---@field on_buf_load? fun(buffer: integer, data: any)

---@alias resession.Hook "pre_save"|"post_save"|"pre_load"|"post_load"

--- All save/load hooks receive these options.
---@class continuity.HookOpts
---@field session_file string The path to the session file
---@field state_dir string The path to the directory holding session-associated data
---@field attach? boolean Loading: Attach to session after restoring. Saving: Attach to/detach from session after saving.
---@field meta? table External data remembered in association with this session. Useful to build on top of the core API.
---@field reset? boolean Close everything associated with the session (saving)/other sessions (loading) after the operation.
---@field autosave_enabled? boolean When this session is attached, automatically save it in intervals. Defaults to the global setting `session.autosave_enabled`.
---@field autosave_interval? integer Seconds between autosaves of this session, if enabled. Defaults to the global setting `session.autosave_interval`.
---@field autosave_notify? boolean Trigger a notification when autosaving this session. Defaults to the global setting `session.autosave_notify`.
---@field options? string[] Save and restore these options. Defaults to the global setting `session.options`.
---@field buf_filter? fun(bufnr: integer, opts: continuity.SnapshotOpts): boolean Custom logic for determining if the buffer should be included. Defaults to the global setting `session.buf_filter`.
---@field tab_buf_filter? fun(tabpage: integer, bufnr: integer, opts: continuity.SnapshotOpts): boolean Custom logic for determining if a buffer should be included in a tab-scoped session. Defaults to the global setting `session.tab_buf_filter`.
---@field modified? boolean|"auto" Save/load modified buffers and their undo history. If set to `auto`, does not save, but still loads modified buffers. Defaults to the global setting `session.modified`.

---@alias continuity.LoadHook fun(name: string, opts: continuity.HookOpts)[]
---@alias continuity.SaveHook fun(name: string, opts: continuity.HookOpts, target_tabpage: continuity.TabNr?)[]

---@alias continuity.BufUUID string
---@alias continuity.WinID integer
---@alias continuity.WinNr integer
---@alias continuity.BufNr integer
---@alias continuity.TabNr integer

---@class continuity.WinInfo
---@field bufname string The name of the buffer that's displayed in the window.
---@field bufuuid continuity.BufUUID The buffer's UUID to track it over multiple sessions.
---@field current boolean Whether the window was the active one when saved.
---@field cursor [integer, integer] (row, col) tuple of the cursor position, mark-like => (1, 0)-indexed
---@field width integer Width of the window in number of columns.
---@field height integer Height of the window in number of rows.
---@field options table<string, any> Window-scoped options.
---@field cwd? string If a local working directory was set for the window, its path.
---@field extension_data? any If the window is supported by an extension, the data it needs to remember.
---@field extension? string If the window is supported by an extension, the name of the extension.

---@class continuity.WinInfoRestored: continuity.WinInfo
---@field winid continuity.WinID The window ID of the restored window in the current session

---@class continuity.WinLayoutLeaf
---@field [1] "leaf" Node type
---@field [2] continuity.WinInfo Saved window info

---@class continuity.WinLayoutLeafRestored: continuity.WinLayoutLeaf
---@field [2] continuity.WinInfoRestored Saved/restored window info

---@class continuity.WinLayoutBranch
---@field [1] "row" | "col" Node type
---@field [2] (continuity.WinLayoutLeaf|continuity.WinLayoutBranch)[] children

---@class continuity.WinLayoutBranchRestored: continuity.WinLayoutBranch
---@field [2] (continuity.WinLayoutLeafRestored|continuity.WinLayoutBranchRestored)[] children

---@alias continuity.WinLayout
---| continuity.WinLayoutLeaf
---| continuity.WinLayoutBranch

---@alias continuity.WinLayoutRestored
---| continuity.WinLayoutLeafRestored
---| continuity.WinLayoutBranchRestored

---@class continuity.GlobalData
---@field cwd string
---@field height integer
---@field width integer
---@field options table<string, any>

---@class continuity.BufData
---@field name string
---@field loaded boolean
---@field options table<string, any>
---@field last_pos [integer, integer]
---@field uuid string
---@field in_win boolean

---@class continuity.TabData
---@field options table<string, any>
---@field wins continuity.WinLayout
---@field cwd string?

---@class continuity.Snapshot
---@field buffers continuity.BufData[]
---@field tabs continuity.TabData[]
---@field tab_scoped boolean
---@field global continuity.GlobalData
---@field modified table<continuity.BufUUID, true?>?

---@alias continuity.AttachHook fun(session: continuity.IdleSession)
--- Detach hooks can modify detach opts in place or return new ones.
---@alias continuity.DetachHook fun(session: continuity.ActiveSession, reason: continuity.DetachReason, opts: continuity.DetachOpts): continuity.DetachOpts?

--- Options to influence which data is included in a snapshot.
---@class continuity.SnapshotOpts
---@field options? string[] Save and restore these options
---@field buf_filter? fun(bufnr: integer, opts: continuity.SnapshotOpts): boolean Custom logic for determining if the buffer should be included
---@field tab_buf_filter? fun(tabpage: integer, bufnr: integer, opts: continuity.SnapshotOpts): boolean Custom logic for determining if a buffer should be included in a tab-scoped session
---@field modified? boolean|"auto" Save/load modified buffers and their undo history. If set to `auto` (default), does not save, but still loads modified buffers.

--- Options to influence how an attached session is handled.
---@class continuity.SessionOpts: continuity.SnapshotOpts
---@field autosave_enabled? boolean When this session is attached, automatically save it in intervals. Defaults to false.
---@field autosave_interval? integer Seconds between autosaves of this session, if enabled. Defaults to 60.
---@field autosave_notify? boolean Trigger a notification when autosaving this session. Defaults to true.
---@field on_attach? continuity.AttachHook A function that's called when attaching to this session. No global default.
---@field on_detach? continuity.DetachHook A function that's called when detaching from this session. No global default.

--- Session-associated configuration, rendered from passed options and default config.
---@class continuity.SessionConfig: continuity.SnapshotOpts
---@field session_file string The path to the session file
---@field state_dir string The path to the directory holding session-associated data
---@field autosave_enabled boolean When this session is attached, automatically save it in intervals.
---@field autosave_interval integer Seconds between autosaves of this session, if enabled.
---@field autosave_notify? boolean Trigger a notification when autosaving this session. Defaults to the global setting `session.autosave_notify`/`true`.
---@field meta? table External data remembered in association with this session. Useful to build on top of the core API.

---@class continuity.ActiveSessionInfo: continuity.SessionConfig
---@field name string The name of the session
---@field tabnr (continuity.TabNr|true)? The tab the session is attached to, if any. Can be `true`, which indicates it's a tab-scoped session that has not been restored yet - although not when requesting via the API
---@field tab_scoped boolean Whether the session is tab-scoped

---@class continuity.BufContext
---@field bufnr continuity.BufNr The buffer number of the buffer this context references
---@field name string The name of the buffer this context references. Usually the path of the loaded file or the empty string for untitled ones.
---@field uuid continuity.BufUUID A UUID to track buffers across session restorations
---@field last_buffer_pos? [integer, integer] cursor position when last exiting the buffer
---@field last_win_pos? table<string, [integer, integer]> Window (ID as string)-specific cursor positions
---@field need_edit? boolean Indicates the buffer needs :edit to be initialized correctly (autocmds are suppressed during session load)
---@field needs_restore? boolean Indicates the buffer has been loaded during session load, but has not been initialized completely because it never has been accessed
---@field restore_last_pos? boolean Indicates the buffer cursor needs to be restored. Handled during initial session loading e.g. for previews and again in buffer initialization when loaded into a window.
---@field state_dir? string The directory to save session-associated state in. Used for modification persistence.
---@field swapfile? string The path to the buffer's swapfile if it had one when loaded.
---@field unrestored? boolean Indicates the buffer could not be restored properly because it had a swapfile and was opened read-only

-- The following type definitions are quite painful at the moment. I'm unsure how to type this
-- properly/whether emmylua just misses the functionality.
-- Specifically, the :attach() and :restore() methods caused a lot of headaches.

---------------------------------------------------------------------------------------------------
-- 0. Common session data/behavior
---------------------------------------------------------------------------------------------------

--- The associated session is tab-scoped to this specific tab
---@class continuity.TabTarget
---@field tab_scoped true
---@field tabnr continuity.TabNr

--- The associated session is global-scoped
---@class continuity.GlobalTarget
---@field tab_scoped false
---@field tabnr nil

---@alias continuity.SessionTarget continuity.TabTarget|continuity.GlobalTarget

--- Common session behavior.
---@class continuity.Session<T: continuity.SessionTarget>: T, continuity.SessionConfig
---@field name string
---@field tab_scoped boolean
---@field tabnr continuity.TabNr?
---@field _on_attach continuity.AttachHook[]
---@field _on_detach continuity.DetachHook[]
local Session = {}

--- Create a new session object. `needs_restore` indicates that the
--- snapshot was loaded from a file and has not yet been restored into neovim.
---@param name string
---@param session_file string
---@param state_dir string
---@param opts continuity.LoadOpts|continuity.SaveOpts
---@return continuity.IdleSession<continuity.GlobalTarget>
function Session.new(name, session_file, state_dir, opts) end
---@param name string
---@param session_file string
---@param state_dir string
---@param opts continuity.LoadOpts|continuity.SaveOpts
---@param tabnr continuity.TabNr
---@return continuity.IdleSession<continuity.TabTarget>
function Session.new(name, session_file, state_dir, opts, tabnr) end
---@param name string
---@param session_file string
---@param state_dir string
---@param opts continuity.LoadOpts|continuity.SaveOpts
---@param tabnr nil
---@param needs_restore true
---@return continuity.PendingSession<continuity.GlobalTarget>
function Session.new(name, session_file, state_dir, opts, tabnr, needs_restore) end
---@param name string
---@param session_file string
---@param state_dir string
---@param opts continuity.LoadOpts|continuity.SaveOpts
---@param tabnr true
---@param needs_restore true
---@return continuity.PendingSession<continuity.TabTarget>
function Session.new(name, session_file, state_dir, opts, tabnr, needs_restore) end

--- Create a new session by loading a snapshot, which you need to restore explicitly.
---@param name string
---@param session_file string
---@param state_dir string
---@param opts continuity.LoadOpts
---@return continuity.PendingSession<T>? loaded_session The session object, if it could be loaded
---@return continuity.Snapshot? snapshot The snapshot data, if it could be loaded
function Session.from_snapshot(name, session_file, state_dir, opts) end

--- Add hooks to attach/detach events for this session.
---@param event "attach"
---@param hook continuity.AttachHook
---@return self
function Session:add_hook(event, hook) end
---@param event "detach"
---@param hook continuity.DetachHook
---@return self
function Session:add_hook(event, hook) end

--- Update modifiable options without attaching/detaching a session
---@param opts continuity.LoadOpts|continuity.SaveOpts
---@return boolean modified
function Session:update(opts) end

--- Options for basic snapshot restoration (different from session restoration)
---@class continuity.core.Session.RestoreOpts
---@field reset? boolean Close everything in this neovim instance (note: this happens outside regular session handling, does not trigger autosave). If unset/false, loads the snapshot into one or several clean tabs.
---@field silence_errors? boolean Don't error when this session's `state_file` is missing.
---@field [any] any Any unhandled opts are also passed through to hooks, unless they are session-specific.

--- Restore a snapshot from disk or memory
---@param opts? continuity.core.Session.RestoreOpts
---@param snapshot? continuity.Snapshot Snapshot to restore. If unspecified, loads from file.
---@return continuity.IdleSession<T> self The object itself, but now attachable
---@return boolean success Whether restoration was successful. Only sensible when `silence_errors` is true.
function Session:restore(opts, snapshot) end

--- Check whether this session is attached correctly.
--- Note: It must be the same instance that `:attach()` was called on, not a copy.
---@return TypeGuard<continuity.ActiveSession<T>>
function Session:is_attached() end -- I couldn't make TypeGuard<ActiveSession<T>> work properly with method syntax

--- Turn the session object into opts for snapshot restore/save operations
---@return continuity.SaveOpts|continuity.LoadOpts|continuity.HookOpts
function Session:opts() end

--- Get information about this session
---@return continuity.ActiveSessionInfo
function Session:info() end

--- Delete a saved session
---@param opts? {notify?: boolean, silence_errors?: boolean}
function Session:delete(opts) end

---------------------------------------------------------------------------------------------------
-- 1. Unrestored session, loaded from disk. Needs to be `:restore()`d before we can work with it.
---------------------------------------------------------------------------------------------------

--- Represents a session that has been loaded from a snapshot and needs
--- to be applied still before being able to attach it.
---@class continuity.PendingSession<T: continuity.SessionTarget>: continuity.Session<T>
---@field needs_restore true
local PendingSession = {}

---------------------------------------------------------------------------------------------------
-- 2. Unattached session, either restored from disk or freshly created.
---------------------------------------------------------------------------------------------------

--- A general session config that can be attached, turning it into an active session.
---@class continuity.IdleSession<T: continuity.SessionTarget>: continuity.Session<T>
local IdleSession = {}

--- Attach this session. If it was loaded from a snapshot file, you must ensure you restore
--- the snapshot (`:restore()`) before calling this method.
--- It's fine to attach an already attached session.
---@return continuity.ActiveSession<T>
function IdleSession:attach() end

---@param opts? continuity.SaveAllOpts
---@param hook_opts? {attach?: boolean, reset?: boolean} Options that need to be passed through to pre_save/post_save hooks.
---@return boolean success
function IdleSession:save(opts, hook_opts) end

---------------------------------------------------------------------------------------------------
-- 3. Attached session allow autosave and detaching
---------------------------------------------------------------------------------------------------

--- An active (attached) session.
---@class continuity.ActiveSession<T: continuity.SessionTarget>: continuity.IdleSession<T>
---@field autosave_enabled boolean Autosave this attached session in intervals and when detaching
---@field autosave_interval integer Seconds between autosaves of this session, if enabled.
---@field _aug integer Neovim augroup for this session
---@field _timer uv.uv_timer_t? Autosave timer, if enabled
---@field private _setup_autosave fun(self: continuity.ActiveSession<T>): nil
local ActiveSession = {}

---@param opts? continuity.SaveAllOpts
---@param force? boolean
function ActiveSession:autosave(opts, force) end

--- Detach from this session. Ensure the session is attached before trying to detach,
--- otherwise you'll receive an error.
--- Hint: If you are sure the session should be attached, but still receive an error,
--- ensure that you call `detach()` on the specific session instance you called `:attach()` on before, not a copy.
---@param self continuity.ActiveSession<T>
---@param reason continuity.DetachReason
---@param opts continuity.DetachOpts
---@return continuity.IdleSession<T>
function ActiveSession:detach(reason, opts) end

--- Mark a **tab** session as invalid (i.e. remembered as attached, but its tab is gone).
--- Removes associated resources, skips autosave.
---@param self continuity.ActiveSession<continuity.TabTarget>
---@return continuity.IdleSession<continuity.TabTarget>
function ActiveSession:forget() end

--- Restore a snapshot from disk or memory
--- It seems emmylua does not pick up this override and infers IdleSession<T> instead.
---@param opts? continuity.core.Session.RestoreOpts
---@param snapshot? continuity.Snapshot Snapshot to restore. If unspecified, loads from file.
---@return continuity.ActiveSession<T> self The object itself
---@return boolean success Whether restoration was successful. Only sensible when `silence_errors` is true.
function ActiveSession:restore(opts, snapshot) end

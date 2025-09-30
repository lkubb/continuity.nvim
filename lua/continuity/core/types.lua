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

---@class (exact) resession.SessionInfo
---@field name string Name of the session in the currently active tab
---@field dir string Name of the directory that the session is saved in
---@field tab_scoped boolean Whether the session in the currently active tab is limited to the tab

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

---@class continuity.LoadHookOpts: continuity.HookOpts
---@field silence_errors? boolean Don't error when trying to load a missing session
---@field detach_save? boolean When detaching other sessions, override their autosave behavior

---@class continuity.SaveHookOpts: continuity.HookOpts

---@alias continuity.LoadHook fun(name: string, opts: continuity.LoadHookOpts)[]
---@alias continuity.SaveHook fun(name: string, opts: continuity.SaveHookOpts, target_tabpage: continuity.TabNr?)[]

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

---@alias continuity.AttachHook fun(session: continuity.Session)
--- Detach hooks can modify detach opts in place or return new ones.
---@alias continuity.DetachHook fun(session: continuity.Session, reason: continuity.DetachReason, opts: continuity.DetachOpts): continuity.DetachOpts?

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

---@class continuity.AttachedSessionInfo: continuity.SessionConfig
---@field name string The name of the session
---@field tabnr continuity.TabNr? The tab the session is attached to, if any

---@class continuity.BufContext
---@field bufnr continuity.BufNr The buffer number of the buffer this context references
---@field name string The name of the buffer this context references. Usually the path of the loaded file or the empty string for untitled ones.
---@field uuid continuity.BufUUID A UUID to track buffers across session restorations
---@field last_buffer_pos? [integer, integer] cursor position when last exiting the buffer
---@field last_win_pos? table<string, [integer, integer]> Window (ID as string)-specific cursor positions
---@field need_edit? boolean Indicates the buffer needs :edit to be initialized correctly (autocmds are suppressed during session load)
---@field needs_restore? boolean Indicates the buffer has been loaded during session load, but has not been initialized completely because it never has been accessed
---@field restore_last_pos? boolean Indicates the buffer cursor needs to be restored. Handled during initial session loading e.g. for previews and again in buffer initialization when loaded into a window.
---@field state_dir? string The directory to save session-associated state in. Used for modification persisstence.
---@field swapfile? string The path to the buffer's swapfile if it had one when loaded.
---@field unrestored? boolean Indicates the buffer could not be restored properly because it had a swapfile and was opened read-only

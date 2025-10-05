---@meta

------------------------------
-- Inherited from Resession --
------------------------------

---@class (exact) resession.Extension.OnSaveOpts
---@field tabpage integer? The tabpage being saved, if in a tab-scoped session

--- An extension can save/restore usually unsupported windows or arbitary global state.
--- This is the interface for Resession-compatible extensions.
---@class (exact) resession.Extension
---@field on_save? fun(opts: resession.Extension.OnSaveOpts): any Called when saving a session. Should return necessary state.
---@field on_pre_load? fun(data: any) Called before restoring a session, receives the data returned by `on_save`.
---@field on_post_load? fun(data: any) Called after restoring a session, receives the data returned by `on_save`.
---@field config? fun(options: table) Called when loading the extension, can receive extension-specific configuration.
---@field is_win_supported? fun(winid: integer, bufnr: integer): boolean Called when backing up window layout. Return `true` here to include the window in the snapshot. `save_win` is called after.
---@field save_win? fun(winid: integer): any Called when backing up window layout and `is_win_supported` has returned `true`.
---@field load_win? fun(winid: integer, data: any): integer? Called when restoring window layout. Receives the data returned by `save_win`, should return window ID of the restored window, if successful.

--------------------------
-- Continuity-specific  --
--------------------------
---@namespace continuity

--- Continuity-specific extensions can make use of two additional hooks, which were required when
--- the autosession behavior was implemented as an extension instead of a separate interface.
---@class Extension: resession.Extension
---@field on_post_bufinit? fun(data: any, visible_only: boolean) Called after **visible** buffers were loaded. Receives data from `on_save`. Note that invisible buffers are not loaded at all yet and visible buffers may not have been entered, which is necessary for a complete, functional restoration.
---@field on_buf_load? fun(buffer: integer, data: any) Called when a restored buffer is entered, during the final restoration of the buffer to make it functional. Receives the relevant buffer number and the data returned by `on_save`.

--- Hooks are functions that a **user** can register to subscribe to Continuity's internal events.
--- They are separate from extensions (completely) or `User` autocmds (relatively).
--- This is a list of event identifiers that can be subscribed to.
---@alias Hook "pre_save"|"post_save"|"pre_load"|"post_load"

--- All save/load hooks receive these options.
---@class HookOpts
---@field session_file string The path to the session file
---@field state_dir string The path to the directory holding session-associated data
---@field attach? boolean Loading: Attach to session after restoring. Saving: Attach to/detach from session after saving.
---@field meta? table External data remembered in association with this session. Useful to build on top of the core API.
---@field reset? boolean Close everything associated with the session (saving)/other sessions (loading) after the operation.
---@field autosave_enabled? boolean When this session is attached, automatically save it in intervals. Defaults to the global setting `session.autosave_enabled`.
---@field autosave_interval? integer Seconds between autosaves of this session, if enabled. Defaults to the global setting `session.autosave_interval`.
---@field autosave_notify? boolean Trigger a notification when autosaving this session. Defaults to the global setting `session.autosave_notify`.
---@field options? string[] Save and restore these options. Defaults to the global setting `session.options`.
---@field buf_filter? fun(bufnr: integer, opts: SnapshotOpts): boolean Custom logic for determining if the buffer should be included. Defaults to the global setting `session.buf_filter`.
---@field tab_buf_filter? fun(tabpage: integer, bufnr: integer, opts: SnapshotOpts): boolean Custom logic for determining if a buffer should be included in a tab-scoped session. Defaults to the global setting `session.tab_buf_filter`.
---@field modified? boolean|"auto" Save/load modified buffers and their undo history. If set to `auto`, does not save, but still loads modified buffers. Defaults to the global setting `session.modified`.

--- A function that, after being registered, is called before/after a snapshot is restored.
---@alias LoadHook fun(name: string, opts: HookOpts)[]

--- A function that, after being registered, is called before/after a snapshot is saved.
---@alias SaveHook fun(name: string, opts: HookOpts, target_tabpage: TabNr?)[]

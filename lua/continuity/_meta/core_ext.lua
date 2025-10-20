---@meta

------------------------------
-- Inherited from Resession --
------------------------------

---@class (exact) resession.Extension.OnSaveOpts
---@field tabpage? integer The tabpage being saved, if in a tab-scoped session

--- An extension can save/restore usually unsupported windows or arbitary global state.
--- This is the interface for Resession-compatible extensions.
---@class (exact) resession.Extension
---@field on_save? fun(opts: resession.Extension.OnSaveOpts): any #
---   Called when saving a session. Should return necessary state.
---@field on_pre_load? fun(data: any) #
---   Called before restoring a session, receives the data returned by `on_save`.
---@field on_post_load? fun(data: any) #
---   Called after restoring a session, receives the data returned by `on_save`.
---@field config? fun(options: table) #
---   Called when loading the extension, can receive extension-specific configuration.
---@field is_win_supported? fun(winid: integer, bufnr: integer): boolean #
---   Called when backing up window layout. Return `true` here to include the window in the snapshot.
---   `save_win` is called after.
---@field save_win? fun(winid: integer): any #
---   Called when backing up window layout and `is_win_supported` has returned `true`.
---@field load_win? fun(winid: integer, data: any): integer? #
---   Called when restoring window layout. Receives the data returned by `save_win`,
---   should return window ID of the restored window, if successful.

--------------------------
-- Continuity-specific  --
--------------------------
---@namespace continuity.core

--- Continuity-specific extensions can make use of two additional hooks, which were required when
--- the autosession behavior was implemented as an extension instead of a separate interface.
---@class Extension: resession.Extension
---@field on_save? fun(opts: resession.Extension.OnSaveOpts & snapshot.Context, buflist: continuity.core.snapshot.BufList): any #
---   Called when saving a session. Should return necessary state.
---@field on_pre_load? fun(data: any, opts: snapshot.Context, buflist: string[]) #
---   Called before restoring a session, receives the data returned by `on_save`.
---@field on_post_load? fun(data: any, opts: snapshot.Context, buflist: string[]) #
---   Called after restoring a session, receives the data returned by `on_save`.
---@field on_post_bufinit? fun(data: any, visible_only: boolean) #
---   Called after **visible** buffers were loaded. Receives data from `on_save`.
---   Note that invisible buffers are not loaded at all yet and visible buffers may not have been entered,
---   which is necessary for a complete, functional restoration.
---@field on_buf_load? fun(data: any, buffer: integer) #
---   Called when a restored buffer is entered, during the final restoration of the buffer to make it functional.
---   Receives the relevant buffer number and the data returned by `on_save`.

--- Hooks are functions that a **user** can register to subscribe to Continuity's internal events.
--- They are separate from extensions (completely) or `User` autocmds (relatively).
--- This is a list of event identifiers that can be subscribed to.
---@alias ext.Hook.Save "pre_save"|"post_save"
---@alias ext.Hook.Load "pre_load"|"post_load"
---@alias ext.Hook ext.Hook.Save | ext.Hook.Load

--- All save/load hooks receive these known options (the presence of `dir` depends on the manual `continuity.session` interface though).
--- Unknown ones received via API functions are passed through verbatim.
---@alias ext.HookOpts Session.Init.Paths & Session.Init.Autosave & Session.Init.Meta & snapshot.CreateOpts & Session.KnownHookOpts.SideEffects & Session.KnownHookOpts.Dir & PassthroughOpts

--- A function that, after being registered, is called before/after a snapshot is restored.
---@alias ext.LoadHook fun(name: string, opts: ext.HookOpts)[]

--- A function that, after being registered, is called before/after a snapshot is saved.
---@alias ext.SaveHook fun(name: string, opts: ext.HookOpts, target_tabpage: TabNr?)[]

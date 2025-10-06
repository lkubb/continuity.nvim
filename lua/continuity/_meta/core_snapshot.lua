---@meta
---@namespace continuity.core

--- Options to influence which data is included in a snapshot.
---@class snapshot.CreateOpts
---@field options? string[] Save and restore these options
---@field buf_filter? fun(bufnr: integer, opts: snapshot.CreateOpts): boolean Custom logic for determining if the buffer should be included
---@field tab_buf_filter? fun(tabpage: integer, bufnr: integer, opts: snapshot.CreateOpts): boolean Custom logic for determining if a buffer should be included in a tab-scoped session
---@field modified? boolean|"auto" Save/load modified buffers and their undo history. If set to `auto` (default), does not save, but still loads modified buffers.

---@class snapshot.RestoreOpts
---@field reset? boolean Close everything in this neovim instance. If unset/false, loads the snapshot into one or several clean tabs.
---@field modified? boolean|"auto" If the snapshot contains unsaved buffer modifications, restore them.
---@field state_dir? string Directory session-associated data like unsaved buffer modifications are stored in. Required for `modified` loading.

---@class snapshot.RestoreWithHooksOpts: snapshot.RestoreOpts
---@field [any] any Any unhandled opts are also passed through to hooks

--- A snapshot of nvim's state.
---@class Snapshot
---@field buffers Snapshot.BufData[] Buffer-specific data
---@field tabs Snapshot.TabData[] Tab-specific and window layout data
---@field tab_scoped boolean Whether this snapshot was derived from a single tab
---@field global Snapshot.GlobalData Global snapshot data
---@field modified table<BufUUID, true?>? List of buffers (identified by internal UUID) whose unsaved modifications were backed up in the snapshot

--- Global snapshot data like cwd, height/width and global options.
---@class Snapshot.GlobalData
---@field cwd string Nvim's global cwd.
---@field height integer vim.o.lines - vim.o.cmdheight
---@field width integer vim.o.columns
---@field options table<string, any> Global nvim options

--- Buffer-specific snapshot data like path, loaded state, options and last cursor position.
---@class Snapshot.BufData
---@field name string Name of the buffer, usually its path. Can be empty when unsaved modifications are backed up.
---@field loaded boolean Whether the buffer was loaded.
---@field options table<string, any> Buffer-specific nvim options.
---@field last_pos [integer, integer] Position of the cursor when this buffer was last shown in a window (" mark). Only updated once a buffer becomes invisible. Visible buffer cursors are backed up in the window layout data.
---@field uuid string A buffer-specific UUID intended to track it between sessions. Required to save/restore unnamed buffers.
---@field in_win boolean Whether the buffer is visible in at least one window.

--- Tab-specific (options, cwd) and window layout snapshot data.
---@class Snapshot.TabData
---@field options table<string, any> Tab-specific nvim options. Currently only `cmdheight`.
---@field wins layout.WinLayout Window layout enriched with window-specific snapshot data
---@field cwd string? The tab's cwd, if different from the global one or a tab-scoped snapshot

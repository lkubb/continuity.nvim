---@class (exact) resession.ListOpts
---@field dir? string Name of directory to list (overrides config.dir)

---@class (exact) resession.DeleteOpts
---@field dir? string Name of directory to delete from (overrides config.dir)
---@field notify? boolean Notify on success (default true)

---@class (exact) resession.SaveOpts
---@field attach? boolean Stay attached to session after saving (default true)
---@field notify? boolean Notify on success (default true)
---@field dir? string Name of directory to save to (overrides config.dir)

---@class (exact) resession.SaveAllOpts
---@field notify? boolean Notify on success

---@class (exact) resession.LoadOpts
---@field attach? boolean Attach to session after loading
---@field reset? boolean|"auto" Close everything before loading the session (default "auto")
---@field silence_errors? boolean Don't error when trying to load a missing session
---@field dir? string Name of directory to load from (overrides config.dir)

---@class (exact) resession.Extension.OnSaveOpts
---@field tabpage integer? The tabpage being saved, if in a tab-scoped session

---@class (exact) resession.Extension
---@field on_save? fun(opts: resession.Extension.OnSaveOpts):any
---@field on_pre_load? fun(data: any)
---@field on_post_bufinit? fun(data: any, visible_only: boolean)
---@field on_buf_load? fun(buffer: integer, data: any)
---@field on_post_load? fun(data: any)
---@field config? fun(options: table)
---@field is_win_supported? fun(winid: integer, bufnr: integer): boolean
---@field save_win? fun(winid: integer): any
---@field load_win? fun(winid: integer, data: any): nil|integer

---@class (exact) resession.SessionInfo
---@field name string Name of the current session
---@field dir string Name of the directory that the current session is saved in

---@alias resession.Hook "pre_save"|"post_save"|"pre_load"|"post_load"
---@alias resession.BufUUID string
---@alias resession.WinID integer
---@alias resession.WinNr integer
---@alias resession.BufNr integer
---@alias resession.TabNr integer

---@class resession.WinInfo
---@field bufname string The name of the buffer that's displayed in the window.
---@field bufuuid resession.BufUUID The buffer's UUID to track it over multiple sessions.
---@field current boolean Whether the window was the active one when saved.
---@field cursor [integer, integer] (row, col) tuple of the cursor position, mark-like => (1, 0)-indexed
---@field width integer Width of the window in number of columns.
---@field height integer Height of the window in number of rows.
---@field options table<string, any> Window-scoped options.
---@field cwd? string If a local working directory was set for the window, its path.
---@field extension_data? any If the window is supported by an extension, the data it needs to remember.
---@field extension? string If the window is supported by an extension, the name of the extension.

---@class resession.WinInfoRestored: resession.WinInfo
---@field winid resession.WinID The window ID of the restored window in the current session

---@class resession.WinLayoutLeaf
---@field [1] "leaf" Node type
---@field [2] resession.WinInfo Saved window info

---@class resession.WinLayoutLeafRestored: resession.WinLayoutLeaf
---@field [2] resession.WinInfoRestored Saved/restored window info

---@class resession.WinLayoutBranch
---@field [1] "row" | "col" Node type
---@field [2] (resession.WinLayoutLeaf|resession.WinLayoutBranch)[] children

---@class resession.WinLayoutBranchRestored: resession.WinLayoutBranch
---@field [2] (resession.WinLayoutLeafRestored|resession.WinLayoutBranchRestored)[] children

---@alias resession.WinLayout
---| resession.WinLayoutLeaf
---| resession.WinLayoutBranch

---@alias resession.WinLayoutRestored
---| resession.WinLayoutLeafRestored
---| resession.WinLayoutBranchRestored

---@class resession.GlobalData
---@field cwd string
---@field height integer
---@field width integer
---@field options table<string, any>

---@class resession.BufData
---@field name string
---@field loaded boolean
---@field options table<string, any>
---@field last_pos [integer, integer]
---@field uuid string
---@field in_win boolean

---@class resession.TabData
---@field options table<string, any>
---@field wins resession.WinLayout
---@field cwd string?

---@class resession.SessionData
---@field buffers resession.BufData[]
---@field tabs resession.TabData[]
---@field tab_scoped boolean
---@field global resession.GlobalData

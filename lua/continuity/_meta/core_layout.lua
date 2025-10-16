---@meta
---@namespace continuity.core.layout
---@using continuity.core

--- Window-specific snapshot data
---@class WinInfo
---@field bufname string The name of the buffer that's displayed in the window.
---@field bufuuid BufUUID The buffer's UUID to track it over multiple sessions.
---@field current boolean Whether the window was the active one when saved.
---@field cursor AnonymousMark (row, col) tuple of the cursor position, mark-like => (1, 0)-indexed
---@field width integer Width of the window in number of columns.
---@field height integer Height of the window in number of rows.
---@field options table<string, any> Window-scoped options.
---@field cwd? string If a local working directory was set for the window, its path.
---@field extension_data? any If the window is supported by an extension, the data it needs to remember.
---@field extension? string If the window is supported by an extension, the name of the extension.
---@field jumps? [WinInfo.JumplistEntry[], integer] Window-local jumplist, number of steps from last entry to currently active one
---@field alt? string The alternate file for this window, if any

---@class WinInfo.JumplistEntry: FileMark
-- TODO: coladd?

--- Window-specific snapshot data after it has been restored. Contains the restored window's ID.
---@class WinInfoRestored: WinInfo
---@field winid WinID The window ID of the restored window in the current session

---@class WinLayoutLeaf
---@field [1] "leaf" Node type
---@field [2] WinInfo Saved window info

---@class WinLayoutLeafRestored: WinLayoutLeaf
---@field [2] WinInfoRestored Saved/restored window info

---@class WinLayoutBranch
---@field [1] "row" | "col" Node type
---@field [2] (WinLayoutLeaf|WinLayoutBranch)[] children

---@class WinLayoutBranchRestored: WinLayoutBranch
---@field [2] (WinLayoutLeafRestored|WinLayoutBranchRestored)[] children

---@alias WinLayout
---| WinLayoutLeaf
---| WinLayoutBranch

---@alias WinLayoutRestored
---| WinLayoutLeafRestored
---| WinLayoutBranchRestored

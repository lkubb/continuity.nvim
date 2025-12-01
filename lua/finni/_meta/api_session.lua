---@meta

------------------------------
-- Inherited from Resession --
--   (kept for reference)   --
------------------------------

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

--------------------
-- Finni-specific --
--------------------
---@namespace finni.session
---@using finni.core
---@using finni.SideEffects

---@class DirParam
---@field dir? string Name of session directory (overrides config.dir)

--- API options for `session.list`
---@alias ListOpts DirParam

--- API options for `session.delete`
---@alias DeleteOpts DirParam & Notify & Reset & SilenceErrors

--- API options for `session.save`
---@alias SaveOpts DirParam & Session.InitOptsWithMeta & Attach & Notify & Reset

--- API options for `session.save_all`
---@alias SaveAllOpts Notify

--- API options for `session.load`
---@alias LoadOpts DirParam & Session.InitOptsWithMeta & Attach & ResetAuto & Save & SilenceErrors
---@alias LoadOptsParsed LoadOpts & Reset

--- API options for `session.detach`
---@alias DetachOpts Reset & Save

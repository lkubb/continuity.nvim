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

--------------------------
-- Continuity-specific  --
--------------------------
---@namespace continuity.session
---@using continuity.core

--- API options for `session.list`
---@class ListOpts: resession.ListOpts
---@field dir? string Name of directory to list (overrides config.dir)

--- API options for `session.delete`
---@class DeleteOpts: resession.DeleteOpts
---@field dir? string Name of directory to delete from (overrides config.dir)
---@field notify? boolean Notify on success (default true)
---@field reset? boolean When deleting an attached session, close all associated tabpages. Defaults to false.
---@field silence_errors? boolean Don't error when trying to delete a non-existent session

--- API options for `session.save`
---@class SaveOpts: Session.InitOpts, resession.SaveOpts
---@field attach? boolean Stay attached to session after saving (default true)
---@field dir? string Name of directory to save to (overrides config.dir)
---@field meta? table External data remembered in association with this session. Useful to build on top of the core API.
---@field notify? boolean Notify on success (default true)
---@field reset? boolean When not staying attached to the session, close all associated tabpages. Defaults to false.

--- API options for `session.save_all`
---@class SaveAllOpts: resession.SaveAllOpts
---@field notify? boolean Notify on success

--- API options for `session.load`
---@class LoadOpts: Session.InitOpts, resession.LoadOpts
---@field attach? boolean Attach to session after loading
---@field detach_save? boolean When detaching other sessions, override their autosave behavior
---@field dir? string Name of directory to load from (overrides config.dir)
---@field meta? table External data remembered in association with this session. Useful to build on top of the core API.
---@field reset? boolean|"auto" Close everything before loading the session (default "auto")
---@field silence_errors? boolean Don't error when trying to load a missing session

--- API options for `session.detach`
---@class DetachOpts
---@field reset? boolean Whether to close all session-associated tabpages. Defaults to false.
---@field save? boolean Whether to save the session before detaching

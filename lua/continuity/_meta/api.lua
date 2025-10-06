---@meta
---@namespace continuity

---@class SideEffects.Attach
---@field attach? boolean Attach to/stay attached to session after operation

---@class (exact) SideEffects.ResetAuto
---@field reset? boolean|"auto" When detaching a session in the process, unload associated resources/reset everything during the operation when restoring a snapshot. `auto` resets only for global sessions.

---@class (exact) SideEffects.Reset
---@field reset? boolean When detaching a session in the process, unload associated resources/reset everything during the operation when restoring a snapshot.

---@class SideEffects.Notify
---@field notify? boolean Notify on success

---@class SideEffects.Save
---@field save? boolean Save/override autosave config for affected sessions before the operation

---@class SideEffects.SilenceErrors
---@field silence_errors? boolean Don't error during this operation

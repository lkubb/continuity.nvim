---@type resession.Extension
local M = {}

---Get the saved data for this extension
---@param _ resession.Extension.OnSaveOpts Information about the session being saved
---@return table?
M.on_save = function(_)
  return require("continuity").save_modified_buffers()
end

-- ---Restore the extension state
-- ---@param data table The value returned from on_save
-- M.on_pre_load = function(data)
--   -- This is run before the buffers, windows, and tabs are restored
-- end

---Restore modified buffers for presentation purposes.
---@param data table The value returned from on_save
M.on_post_bufinit = function(data, visible_only)
  local continuity = require("continuity")
  continuity.restore_modified_buffers(data, visible_only)
end

---Restore modified buffer when re-:edit-ed.
M.on_buf_load = function(buf, data)
  local continuity = require("continuity")
  continuity.restore_modified_buffer(buf, data)
end

-- ---Called when resession gets configured
-- ---This function is optional
-- ---@param data table The configuration data passed in the config
-- M.config = function(data)
--   --
-- end

-- ---Check if a window is supported by this extension
-- ---This function is optional, but if provided save_win and load_win must
-- ---also be present.
-- ---@param winid integer
-- ---@param bufnr integer
-- ---@return boolean
-- M.is_win_supported = function(winid, bufnr)
--   return false
-- end
--
-- ---Save data for a window
-- ---@param winid integer
-- ---@return any
-- M.save_win = function(winid)
--   -- This is used to save the data for a specific window that contains a non-file buffer (e.g. a filetree).
--   return {}
-- end
--
-- ---Called with the data from save_win
-- ---@param winid integer
-- ---@param config any
-- ---@return integer|nil If the original window has been replaced, return the new ID that should replace it
-- M.load_win = function(winid, config)
--   -- Restore the window from the config
-- end

return M

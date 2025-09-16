local config = require("resession.config")
local util = require("resession.util")
local M = {}

--- Check if a window should be saved. If so, return relevant information.
--- Only exposed for testing purposes
---@private
---@param tabnr integer The number of the tab that contains the window
---@param winid resession.WinID The window id of the window to query
---@param current_win integer The window id of the currently active window
---@return resession.WinInfo|false
M.get_win_info = function(tabnr, winid, current_win)
  local bufnr = vim.api.nvim_win_get_buf(winid)
  local win = {}
  local supported_by_ext = false
  for ext_name in pairs(config.extensions) do
    local ext = util.get_extension(ext_name)
    if ext and ext.is_win_supported and ext.is_win_supported(winid, bufnr) then
      ---@diagnostic disable-next-line: param-type-not-match
      local ok, extension_data = pcall(ext.save_win, winid)
      if ok then
        ---@cast extension_data -string
        win.extension_data = extension_data
        win.extension = ext_name
        supported_by_ext = true
      else
        vim.notify(
          string.format('[resession] Extension "%s" save_win error: %s', ext_name, extension_data),
          vim.log.levels.ERROR
        )
      end
      break
    end
  end
  if not supported_by_ext and not config.buf_filter(bufnr) then
    return false
  end
  win = vim.tbl_extend("error", win, {
    bufname = vim.api.nvim_buf_get_name(bufnr),
    bufuuid = vim.b[
      bufnr --[[@as integer]]
    ].resession_uuid,
    current = winid == current_win,
    cursor = vim.api.nvim_win_get_cursor(winid),
    width = vim.api.nvim_win_get_width(winid),
    height = vim.api.nvim_win_get_height(winid),
    options = util.save_win_options(winid),
  })
  ---@cast win resession.WinInfo
  local winnr = vim.api.nvim_win_get_number(winid)
  if vim.fn.haslocaldir(winnr, tabnr) == 1 then
    win.cwd = vim.fn.getcwd(winnr, tabnr)
  end
  return win
end

--- Process a tabpage's window layout as returned by `vim.fn.winlayout`.
--- Filters unsupported buffers, collapses resulting empty branches and
--- adds necessary information to leaf nodes (windows).
---@param tabnr integer
---@param layout vim.fn.winlayout.ret
---@param current_win integer
---@return resession.WinLayout|false
M.add_win_info_to_layout = function(tabnr, layout, current_win)
  ---@diagnostic disable-next-line: undefined-field
  ---@type 'leaf'|'col'|'row'|nil
  local typ = layout[1]
  if typ == "leaf" then
    ---@cast layout vim.fn.winlayout.leaf
    local res = M.get_win_info(tabnr, layout[2], current_win)
    return res and { "leaf", res } or false
  elseif typ then
    ---@cast layout vim.fn.winlayout.branch
    local items = {}
    for _, v in ipairs(layout[2]) do
      local ret = M.add_win_info_to_layout(tabnr, v, current_win)
      if ret then
        items[#items + 1] = ret
      end
    end
    if #items == 1 then
      return items[1]
    elseif #items == 0 then
      return false
    else
      return { typ, items }
    end
  end
  return false
end

--- Create all windows in the saved layout. Add created window ID information to leaves.
---@param layout resession.WinLayoutLeaf|resession.WinLayoutBranch The window layout to apply, as returned by `add_win_info_to_layout`
---@return resession.WinLayoutRestored
local function set_winlayout(layout)
  local typ = layout[1]
  if typ == "leaf" then
    ---@cast layout resession.WinLayoutLeaf
    ---@type resession.WinInfoRestored
    local win = layout[2]
    ---@type resession.WinID
    local winid = vim.api.nvim_get_current_win()
    win.winid = winid
    if win.cwd then
      vim.cmd(string.format("lcd %s", win.cwd))
    end
  else
    ---@cast layout resession.WinLayoutBranch
    local winids = {}
    local splitright = vim.opt.splitright
    local splitbelow = vim.opt.splitbelow
    vim.opt.splitright = true
    vim.opt.splitbelow = true
    for i in ipairs(layout[2]) do
      if i > 1 then
        if typ == "row" then
          vim.cmd("vsplit")
        else
          vim.cmd("split")
        end
      end
      table.insert(winids, vim.api.nvim_get_current_win())
    end
    vim.opt.splitright = splitright
    vim.opt.splitbelow = splitbelow
    for i, v in ipairs(layout[2]) do
      vim.api.nvim_set_current_win(winids[i])
      set_winlayout(v)
    end
  end
  return layout
end

---@param base integer
---@param factor number
---@return integer
local function scale(base, factor)
  return math.floor(base * factor + 0.5)
end

--- Apply saved data to restored windows. Calls extensions or loads files, then restores options and dimensions
---@param layout resession.WinLayoutLeafRestored|resession.WinLayoutBranchRestored
---@param scale_factor [number, number] Scaling factor for [width, height]
---@return resession.WinLayoutRestored
---@return {winid?: resession.WinID}
local function set_winlayout_data(layout, scale_factor, visit_data)
  local log = require("resession.log")
  local typ = layout[1]
  if typ == "leaf" then
    ---@cast layout resession.WinLayoutLeafRestored
    local win = layout[2]
    vim.api.nvim_set_current_win(win.winid)
    if win.extension then
      local ext = util.get_extension(win.extension)
      if ext and ext.load_win then
        -- Re-enable autocmds so if the extensions rely on BufReadCmd it works
        vim.o.eventignore = ""
        local ok, new_winid = pcall(ext.load_win, win.winid, win.extension_data)
        vim.o.eventignore = "all"
        if ok then
          ---@cast new_winid resession.WinID
          new_winid = new_winid or win.winid
          win.winid = new_winid
        else
          vim.notify(
            string.format('[resession] Extension "%s" load_win error: %s', win.extension, new_winid),
            vim.log.levels.ERROR
          )
        end
      end
    else
      local bufnr = util.ensure_buf(win.bufname, win.bufuuid)
      log.fmt_debug("Loading buffer %s (uuid: %s) in win %s", win.bufname, win.bufuuid, win.winid)
      vim.api.nvim_win_set_buf(win.winid, bufnr)
      -- After setting the buffer into the window, manually set the filetype to trigger syntax highlighting
      log.fmt_trace("Triggering filetype from winlayout for buf %s", bufnr)
      vim.o.eventignore = ""
      vim.bo[bufnr].filetype = vim.bo[bufnr].filetype
      vim.o.eventignore = "all"
      -- Save the last position of the cursor in case buf_load plugins
      -- change the buffer text and request restoration
      local temp_pos_table = vim.b[bufnr].resession_last_win_pos or {}
      temp_pos_table[tostring(win.winid)] = win.cursor
      vim.b[bufnr].resession_last_win_pos = temp_pos_table
      -- We don't need to restore last cursor position on buffer load
      -- because the triggered :edit command keeps it
      vim.b[bufnr].resession_restore_last_pos = nil
    end
    util.restore_win_options(win.winid, win.options)
    local width_scale = vim.wo.winfixwidth and 1 or scale_factor[1]
    ---@cast width_scale number
    vim.api.nvim_win_set_width(win.winid --[[@as integer]], scale(win.width, width_scale))
    local height_scale = vim.wo.winfixheight and 1 or scale_factor[2]
    ---@cast height_scale number
    vim.api.nvim_win_set_height(win.winid --[[@as integer]], scale(win.height, height_scale))
    log.fmt_debug(
      "Restoring cursor for buf %s (uuid: %s) in win %s to %s",
      win.bufname,
      win.bufuuid or "nil",
      win.winid or "nil",
      win.cursor or "nil"
    )
    local ok, err = pcall(vim.api.nvim_win_set_cursor, win.winid --[[@as integer]], win.cursor)
    if not ok then
      log.fmt_error(
        "Failed restoring cursor for bufnr %s (uuid: %s) in win %s to %s: %s",
        win.bufname,
        win.bufuuid or "nil",
        win.winid or "nil",
        win.cursor or "nil",
        err
      )
    end
    if win.current then
      visit_data.winid = win.winid
    end
  else
    for _, v in ipairs(layout[2]) do
      set_winlayout_data(v, scale_factor, visit_data)
    end
  end
  -- Make it somewhat explicit that we're modifying dicts in-place
  return layout, visit_data
end

---@param layout resession.WinLayout|false|nil
---@param scale_factor [number, number] Scaling factor for [width, height]
---@return resession.WinID? The ID of the window that should have focus after session load
M.set_winlayout = function(layout, scale_factor)
  if not layout then
    return
  end
  layout = set_winlayout(layout)
  local visit_data = {}
  layout, visit_data = set_winlayout_data(layout, scale_factor, visit_data)
  return visit_data.winid
end

return M

local Buf = require("continuity.core.buf")
local Config = require("continuity.config")
local Ext = require("continuity.core.ext")
local util = require("continuity.util")

local lazy_require = util.lazy_require
local log = lazy_require("continuity.log")

---@class continuity.core.layout
local M = {}

---@namespace continuity.core.layout
---@using continuity.core

--- Check if a window should be saved. If so, return relevant information.
--- Only exposed for testing purposes
---@private
---@param tabnr integer The number of the tab that contains the window
---@param winid WinID The window id of the window to query
---@param current_win integer The window id of the currently active window
---@param opts snapshot.CreateOpts
---@return WinInfo|false
function M.get_win_info(tabnr, winid, current_win, opts)
  local bufnr = vim.api.nvim_win_get_buf(winid)
  local win = {}
  local supported_by_ext = false
  for ext_name in pairs(Config.extensions) do
    local extmod = Ext.get(ext_name)
    if extmod and extmod.is_win_supported and extmod.is_win_supported(winid, bufnr) then
      ---@diagnostic disable-next-line: param-type-not-match
      local ok, extension_data = pcall(extmod.save_win, winid)
      if ok then
        ---@cast extension_data -string
        win.extension_data = extension_data
        win.extension = ext_name
        supported_by_ext = true
      else
        vim.notify(
          string.format('[continuity] Extension "%s" save_win error: %s', ext_name, extension_data),
          vim.log.levels.ERROR
        )
      end
      break
    end
  end
  if not supported_by_ext and not (opts.buf_filter or Config.session.buf_filter)(bufnr, opts) then
    -- Don't need to check tab_buf_filter, only called for buffers that are visible in a tab
    return false
  end
  local ctx = Buf.ctx(bufnr)
  win = vim.tbl_extend("error", win, {
    bufname = ctx.name,
    bufuuid = ctx.uuid,
    current = winid == current_win,
    cursor = vim.api.nvim_win_get_cursor(winid),
    width = vim.api.nvim_win_get_width(winid),
    height = vim.api.nvim_win_get_height(winid),
    options = util.opts.get_win(winid, opts.options or Config.session.options),
  })
  ---@cast win WinInfo
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
---@param opts snapshot.CreateOpts
---@return WinLayout|false
function M.add_win_info_to_layout(tabnr, layout, current_win, opts)
  ---@diagnostic disable-next-line: undefined-field
  ---@type "leaf"|"col"|"row"|nil
  local typ = layout[1]
  if typ == "leaf" then
    ---@cast layout vim.fn.winlayout.leaf
    local res = M.get_win_info(tabnr, layout[2], current_win, opts)
    return res and { "leaf", res } or false
  elseif typ then
    ---@cast layout vim.fn.winlayout.branch
    local items = {}
    for _, v in ipairs(layout[2]) do
      local ret = M.add_win_info_to_layout(tabnr, v, current_win, opts)
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
---@param layout WinLayoutLeaf|WinLayoutBranch The window layout to apply, as returned by `add_win_info_to_layout`
---@return WinLayoutRestored
local function set_winlayout(layout)
  local typ = layout[1]
  if typ == "leaf" then
    ---@cast layout WinLayoutLeaf
    ---@type WinInfoRestored
    local win = layout[2]
    ---@type WinID
    local winid = vim.api.nvim_get_current_win()
    win.winid = winid
    if win.cwd then
      vim.cmd(string.format("lcd %s", win.cwd))
    end
  else
    ---@cast layout WinLayoutBranch
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
      winids[#winids + 1] = vim.api.nvim_get_current_win()
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
---@param layout WinLayoutLeafRestored|WinLayoutBranchRestored
---@param scale_factor [number, number] Scaling factor for [width, height]
---@return WinLayoutRestored
---@return {winid?: WinID}
local function set_winlayout_data(layout, scale_factor, visit_data)
  local typ = layout[1]
  if typ == "leaf" then
    ---@cast layout WinLayoutLeafRestored
    local win = layout[2]
    vim.api.nvim_set_current_win(win.winid)
    if win.extension then
      local extmod = Ext.get(win.extension)
      if extmod and extmod.load_win then
        -- Re-enable autocmds so if the extensions rely on BufReadCmd it works
        ---@type boolean, (WinID|string)?
        local ok, new_winid
        util.opts.with({ eventignore = "" }, function()
          ok, new_winid = pcall(extmod.load_win, win.winid, win.extension_data)
        end)
        if ok then
          ---@cast new_winid WinID?
          new_winid = new_winid or win.winid
          win.winid = new_winid
        else
          vim.notify(
            string.format(
              '[continuity] Extension "%s" load_win error: %s',
              win.extension,
              new_winid
            ),
            vim.log.levels.ERROR
          )
        end
      end
    else
      local ctx = Buf.added(win.bufname, win.bufuuid)
      log.fmt_debug("Loading buffer %s (uuid: %s) in win %s", win.bufname, win.bufuuid, win.winid)
      vim.api.nvim_win_set_buf(win.winid, ctx.bufnr)
      -- After setting the buffer into the window, manually set the filetype to trigger syntax highlighting
      log.fmt_trace("Triggering filetype from winlayout for buf %s", ctx.bufnr)
      util.opts.with({ eventignore = "" }, function()
        vim.bo[ctx.bufnr].filetype = vim.bo[ctx.bufnr].filetype
      end)
      -- Save the last position of the cursor in case buf_load plugins
      -- change the buffer text and request restoration
      local temp_pos_table = ctx.last_win_pos or {}
      temp_pos_table[tostring(win.winid)] = win.cursor
      ctx.last_win_pos = temp_pos_table
      -- We don't need to restore last cursor position on buffer load
      -- because the triggered :edit command keeps it
      ctx.restore_last_pos = nil
    end
    util.opts.restore_win(win.winid, win.options)
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
      -- This can e.g. happen when an extension has restored the buffer asynchronously
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

---@param layout WinLayout|false|nil
---@param scale_factor [number, number] Scaling factor for [width, height]
---@return WinID? The ID of the window that should have focus after session load
function M.set_winlayout(layout, scale_factor)
  if not layout or not layout[1] then
    return
  end
  layout = set_winlayout(layout)
  local visit_data = {}
  layout, visit_data = set_winlayout_data(layout, scale_factor, visit_data)
  return visit_data.winid
end

--- Ensure the active tabpage is a clean one.
function M.open_clean_tab()
  -- Detect if we're already in a "clean" tab
  -- (one window, and one empty scratch buffer)
  if #vim.api.nvim_tabpage_list_wins(0) == 1 then
    if vim.api.nvim_buf_get_name(0) == "" then
      local lines = vim.api.nvim_buf_get_lines(0, -1, 2, false)
      if vim.tbl_isempty(lines) then
        vim.bo.buflisted = false
        vim.bo.bufhidden = "wipe"
        return
      end
    end
  end
  vim.cmd.tabnew()
end

--- Force-close all tabs, windows and unload all buffers.
function M.close_everything()
  local is_floating_win = vim.api.nvim_win_get_config(0).relative ~= ""
  if is_floating_win then
    -- Go to the first window, which will not be floating
    vim.cmd.wincmd({ args = { "w" }, count = 1 })
  end

  local scratch = vim.api.nvim_create_buf(false, true)
  vim.bo[scratch].bufhidden = "wipe"
  vim.api.nvim_win_set_buf(0, scratch)
  vim.bo[scratch].buftype = ""
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[bufnr].buflisted then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end
  vim.cmd.tabonly({ mods = { emsg_silent = true } })
  vim.cmd.only({ mods = { emsg_silent = true } })
end

return M

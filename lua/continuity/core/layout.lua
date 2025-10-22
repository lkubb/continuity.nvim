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

--- Get the alternate buffer for a window.
---@param winid WinID Window ID to get alternate buffer for
---@return BufNr? alt_bufnr #
---   Buffer number of alternate buffer
local function get_alternate_buf(winid)
  local bufnr = vim.api.nvim_win_call(winid or 0, function()
    return vim.fn.bufnr("#")
  end)
  if bufnr > 0 then
    return bufnr
  end
end

--- Get the alternate file for a window.
---@param winid WinID Window ID to get alternate file for
---@param opts snapshot.CreateOpts Snapshot creation opts
---@return string? alternate_file #
---   Absolute path to alternate file
local function get_alternate_file(winid, opts)
  local altbuf = get_alternate_buf(winid)
  if not altbuf then
    return
  end
  local name = vim.api.nvim_buf_get_name(altbuf)
  -- NOTE: This doesn't respect tab_buf_filter, issue?
  if name ~= "" and (opts.buf_filter or Config.session.buf_filter)(altbuf, opts) then
    return vim.fn.fnamemodify(name, ":p")
  end
end

--- Parse the window-local jumplist into a format that can be saved.
---@param winid WinID Window ID of window to query
---@param tabnr TabNr Tab number containing the window
---@param winnr WinNr Window number coresponding to `winid` in `tabnr` to query
---@param buflist snapshot.BufList Indexed buffer list
---@return [WinInfo.JumplistEntry[], integer] jumps_backtrack #
---   Tuple of list of jumplist entries and jumplist position, backwards from most recent entry
local function parse_jumplist(winid, tabnr, winnr, buflist)
  if vim.w[winid].continuity_jumplist then
    --- If we're in a restored session that has enabled jumplist restoration and the window
    --- has never been focused, its jumplist has not been restored yet and is available
    --- in `w:continuity_jumplist`. Remember this value. If we enabled saving jumplists
    --- only after the session has been loaded, just fall through and remember whatever nvim gives us.
    return {
      vim
        .iter(vim.w[winid].continuity_jumplist[1])
        :map(function(jump)
          return {
            buflist:add(jump[1]),
            jump[2],
            jump[3],
          }
        end)
        :totable(),
      vim.w[winid].continuity_jumplist[2],
    }
  end
  -- Need to use winnr/tabnr here because using winid only works for active tabpage
  local jumplist = vim.fn.getjumplist(winnr, tabnr)
  local jumps, current_pos = jumplist[1], jumplist[2]
  ---@type WinInfo.JumplistEntry[]
  local parsed = {}
  local filtered_before = 0
  for i, jump in ipairs(jumps) do
    local bufname = vim.api.nvim_buf_get_name(jump.bufnr)
    if bufname ~= "" then
      parsed[#parsed + 1] = {
        buflist:add(vim.fn.fnamemodify(bufname, ":p")),
        jump.lnum,
        jump.col,
      }
    elseif i < current_pos then
      filtered_before = filtered_before + 1
    end
  end
  -- If we filter steps in between because we can't restore jump entries for unnamed buffers,
  -- we need to reduce our backtracking so that another C-o gets to the correct position
  -- Note: The list is 0-indexed. If it has 2 items and we're at item 2, current_pos is 1.
  --       If it has 2 items and we're at another position, current_pos is 2.
  local corrected_pos = current_pos - filtered_before
  return { parsed, math.max(0, #parsed - corrected_pos - 1) }
end

--- Get all location lists for a window, and the currently active position.
--- Don't call this for a loclist window, it just returns the displayed loclist.
---@param winid WinID? Window ID to parse loclists for. Defaults to current one.
---@param buflist snapshot.BufList Indexed buffer list
---@return [Snapshot.QFList[], integer]? loclists_pos #
---   Tuple of parsed loclists and number of currently active one.
---   Nothing if window has no loclists.
local function parse_loclists(winid, buflist)
  winid = winid or 0
  local cnt = vim.fn.getloclist(winid, { nr = "$" }).nr
  local ret = {} ---@type Snapshot.QFList[]
  if cnt <= 0 then
    return
  end
  local pos = vim.fn.getloclist(winid, { nr = 0 }).nr ---@type integer
  for i = 1, cnt do
    local loclist = vim.fn.getloclist(winid, { nr = i, all = 0 })
    ret[#ret + 1] = {
      idx = loclist.idx,
      title = loclist.title,
      context = loclist.context ~= "" and loclist.context or nil,
      efm = loclist.efm,
      quickfixtextfunc = loclist.quickfixtextfunc ~= "" and loclist.quickfixtextfunc or nil,
      items = vim.tbl_map(function(item)
        return {
          filename = item.bufnr and buflist:add(vim.api.nvim_buf_get_name(item.bufnr)),
          module = item.module ~= "" and item.module or nil,
          lnum = item.lnum ~= 1 and item.lnum or nil,
          end_lnum = item.end_lnum ~= 0 and item.end_lnum or nil,
          col = item.col ~= 1 and item.col or nil,
          end_col = item.end_col ~= 0 and item.end_col or nil,
          vcol = item.vcol ~= 0 and item.vcol or nil,
          nr = item.nr ~= 0 and item.nr or nil,
          pattern = item.pattern ~= "" and item.pattern or nil,
          text = item.text,
          type = item.type ~= "" and item.type or nil,
          valid = item.valid ~= 1 and item.valid or nil,
        }
      end, loclist.items),
    }
  end
  return { ret, pos }
end

--- Restore saved loclists.
---@param winid WinID Window ID of the window to restore loclists for
---@param lists Snapshot.QFList[] Saved loclists as returned from `parse_loclists`
---@param pos integer Position of active loclist
---@param buflist string[] Indexed list of buffers, generated during save
local function restore_loclists(winid, lists, pos, buflist)
  winid = winid or 0
  vim.fn.setloclist(winid, {}, "f") -- ensure lists are always cleared
  vim.iter(lists):each(function(loclist)
    loclist.context = loclist.context or ""
    loclist.quicktextfunc = loclist.quicktextfunc or ""
    loclist.items = vim
      .iter(loclist.items or {})
      :map(function(item)
        if item.filename then
          item.filename = buflist[item.filename] or item.filename
        end
        return vim.tbl_extend("keep", item, {
          module = "",
          end_lnum = 0,
          col = 1,
          end_col = 0,
          vcol = 0,
          nr = 0,
          pattern = "",
          type = "",
          valid = 1,
        })
      end)
      :totable()
    vim.fn.setloclist(winid, {}, " ", loclist)
  end)
  vim.api.nvim_win_call(winid, function()
    vim.cmd.lhistory({ count = pos })
  end)
end

local win_restore_group =
  vim.api.nvim_create_augroup("continuity.core.layout.WinRestore", { clear = true })
local win_restore ---@type integer?
--- Can't attach autocmd to WinEnter of specific window, so keep track of
--- windows to restore in this list.
local restore_wins = {} ---@type table<WinID, true?>

--- Ensure jumplist of window is restored, even if several windows
--- show the same buffer.
---@param winid WinID ID of window to ensure restoration for
local function schedule_restore_jumplist(winid)
  win_restore = win_restore
    or vim.api.nvim_create_autocmd("WinEnter", {
      desc = "Continuity: Finish window restoration (jumplists)",
      group = win_restore_group,
      callback = function(ev)
        local curwin = vim.api.nvim_get_current_win()
        if not restore_wins[curwin] then
          return
        end
        if
          (vim.b[ev.buf].continuity_ctx or {}).initialized ~= false
          and vim.w[curwin].continuity_jumplist
        then
          --- This buffer has already been initialized or has not been loaded by Continuity,
          --- so jumplist restoration will not be triggered in BufEnter of `finish_restore_buf`.
          M.restore_jumplist(curwin)
        end
        restore_wins[curwin] = nil
        if vim.tbl_isempty(restore_wins) then
          -- Remove this autocommand once we don't have anything to do anymore
          return true
        end
      end,
    })
  restore_wins[winid] = true
end

--- Check if a window should be saved. If so, return relevant information.
--- Only exposed for testing purposes
---@private
---@param tabnr integer Tab number of the tab that contains the window
---@param winid WinID Window ID of window to query
---@param current_win WinID Window ID of the currently active window
---@param opts snapshot.CreateOpts Snapshot creation opts
---@param buflist snapshot.BufList Indexed buffer list
---@return WinInfo|false wininfo #
function M.get_win_info(tabnr, winid, current_win, opts, buflist)
  local bufnr = vim.api.nvim_win_get_buf(winid)
  local win = {}
  local supported_by_ext = false
  for ext_name in pairs(Config.extensions) do
    local extmod = Ext.get(ext_name)
    if
      extmod
      and extmod.save_win
      and extmod.is_win_supported
      and extmod.is_win_supported(winid, bufnr)
    then
      util.try_log_else(
        extmod.save_win,
        { [1] = 'Extension "%s" save_win error: %s', [2] = ext_name, notify = true },
        function(extension_data)
          win.extension_data = extension_data
          win.extension = ext_name
          supported_by_ext = true
        end,
        winid
      )
      break
    end
  end
  local loclist_win, loclists, is_quickfix
  if vim.bo[bufnr].buftype == "quickfix" then
    is_quickfix = true
    local wininfo = vim.fn.getwininfo(winid)[1] or {}
    if wininfo.quickfix == 1 and wininfo.loclist == 1 then
      loclist_win = vim.fn.getloclist(winid, { filewinid = 0 }).filewinid
    end
  end
  if
    not (supported_by_ext or loclist_win)
    and not (opts.buf_filter or Config.session.buf_filter)(bufnr, opts)
  then
    -- Don't need to check tab_buf_filter, only called for buffers that are visible in a tab
    return false
    -- TODO: Consider preserving layout here, at least if it's the only window in the tabpage
  end
  if not is_quickfix then
    -- Loclist windows don't have loclists, same for the quickfix one I suppose
    loclists = parse_loclists(winid, buflist)
  end
  local ctx = Buf.ctx(bufnr)
  local winnr = vim.api.nvim_win_get_number(winid) ---@type WinNr
  win = vim.tbl_extend("error", win, {
    bufname = ctx.name,
    bufuuid = ctx.uuid,
    current = winid == current_win,
    cursor = vim.api.nvim_win_get_cursor(winid),
    width = vim.api.nvim_win_get_width(winid),
    height = vim.api.nvim_win_get_height(winid),
    options = util.opts.get_win(winid, opts.options or Config.session.options),
    jumps = util.opts.coalesce_auto("jumps", false, opts, Config.session)
      and parse_jumplist(winid, tabnr, winnr, buflist),
    alt = buflist:add(get_alternate_file(winid, opts)),
    loclists = loclists,
    -- We don't need to generate unique IDs for windows, just reuse winids
    -- to be able to track/reference individual windows. We need this info to restore loclist windows.
    loclist_win = loclist_win,
    old_winid = winid,
  })
  ---@cast win WinInfo
  if vim.fn.haslocaldir(winnr, tabnr) == 1 then
    win.cwd = vim.fn.getcwd(winnr, tabnr)
  end
  return win
end

--- Process a tabpage's window layout as returned by `vim.fn.winlayout`.
--- Filters unsupported buffers, collapses resulting empty branches and
--- adds necessary information to leaf nodes (windows).
---@param tabnr TabNr Tab number of tab
---@param layout vim.fn.winlayout.ret Retval of `vim.fn.winlayout()`
---@param current_win WinID ID of current window
---@param opts snapshot.CreateOpts Snapshot creation opts
---@param buflist snapshot.BufList Indexed buffer list
---@return WinLayout|false winlayout #
function M.add_win_info_to_layout(tabnr, layout, current_win, opts, buflist)
  ---@diagnostic disable-next-line: undefined-field
  ---@type "leaf"|"col"|"row"|nil
  local typ = layout[1]
  if typ == "leaf" then
    ---@cast layout vim.fn.winlayout.leaf
    local res = M.get_win_info(tabnr, layout[2], current_win, opts, buflist)
    return res and { "leaf", res } or false
  elseif typ then
    ---@cast layout vim.fn.winlayout.branch
    local items = {}
    for _, v in ipairs(layout[2]) do
      local ret = M.add_win_info_to_layout(tabnr, v, current_win, opts, buflist)
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
---@param layout WinLayoutLeaf|WinLayoutBranch #
---   The window layout to apply, as returned by `add_win_info_to_layout`
---@return WinLayoutRestored restored #
---   Same table as `layout`, but with valid window ID(s) set
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
      vim.cmd.lcd({ args = { vim.fn.fnameescape(win.cwd) } })
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
          vim.cmd("keepjumps keepalt vsplit")
        else
          vim.cmd("keepjumps keepalt split")
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
---@param layout WinLayoutLeafRestored|WinLayoutBranchRestored Snapshot window data with valid window ID
---@param scale_factor [number, number] Scaling factor for [width, height]
---@param buflist string[] Indexed buffer list, generated during save
---@return WinLayoutRestored restored #
---   Same table as `layout`, but with valid window ID(s) set
---@return WinID? active_winid #
---   Window ID of active window, if any
local function set_winlayout_data(layout, scale_factor, buflist)
  local active_winid ---@type WinID?
  local all_wins = {} ---@type table<WinID, WinInfoRestored?>
  local loclist_wins = {} ---@type table<WinID, WinInfoRestored?>
  local winid_old_new = {} ---@type table<WinID, WinID?>

  --- Phase 2 of restoration, after all extensions have run and loclist windows are restored (so window IDs are stable).
  ---@param win WinInfoRestored
  local function restore_final(win)
    -- Ensure the correct window is focused.
    vim.api.nvim_set_current_win(win.winid)
    -- Try to enforce window order in case extensions or loclist window creation have messed it up.
    -- We can only do this inside frames (rows/cols).
    -- This is mostly a workaround because we cannot control where a loclist window opens
    -- and just loading the loclist buffer into an existing window does not set
    -- the correct filewinid. [Maybe could be hacked together via ffi, but... :]]
    -- Just for reference: https://neovim.discourse.group/t/calling-neovim-internal-functions-with-luajit-ffi-and-rust/165
    -- One case where this does not work is when a loclist window was opened,
    -- moved and then the associated window was split in the vertical direction,
    -- resulting in it being put into a new frame without its loclist window.
    -- To replicate this, we would need to replay the same sequence (possibly requiring
    -- a lookahead if the loclist window was moved to before the referenced one).
    -- Moving that state around would be much more involved, so just accept that
    -- we can't restore absolutely everything.
    vim.cmd.wincmd({ "x", count = win.frame_pos })

    -- NOTE: From here on, the active window might be different! The window swap
    -- keeps the active window in the same frame position, not the same window.
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
    util.try_log(vim.api.nvim_win_set_cursor, {
      -- This can e.g. happen when an extension has restored the buffer asynchronously
      "Failed to restore cursor for bufnr %s (uuid: %s) in win %s to %s: %s",
      win.bufname,
      win.bufuuid or "nil",
      win.winid or "nil",
      win.cursor or "nil",
    }, win.winid --[[@as integer]], win.cursor)
    if win.jumps then
      -- Restore jumplist later when the window is actually entered for the first time.
      -- Other restoration steps could otherwise cause modifications of the restored data.
      vim.w[win.winid].continuity_jumplist = {
        vim
          .iter(win.jumps[1])
          :map(function(jump)
            return { buflist[jump[1]] or jump[1], jump[2], jump[3] }
          end)
          :totable(),
        win.jumps[2],
      }
      vim.w[win.winid].continuity_win_cursor = win.cursor
      --- ensure jumplist is restored later, even if BufEnter does not trigger
      --- (already restored buffer/same buffer in two windows)
      schedule_restore_jumplist(win.winid)
    end
    if win.current then
      active_winid = win.winid
    end
  end

  --- Phase 1 of restoration. Restores window contents and loclists.
  --- Might replace some windows.
  ---@param layout_inner WinLayoutLeafRestored|WinLayoutBranchRestored
  ---@param frame_pos integer
  local function winlayout_inner(layout_inner, frame_pos)
    local typ = layout_inner[1]
    if typ == "leaf" then
      ---@cast layout_inner WinLayoutLeafRestored
      local win = layout_inner[2]
      vim.api.nvim_set_current_win(win.winid)
      if win.extension then
        local extmod = Ext.get(win.extension)
        if extmod and extmod.load_win then
          -- Re-enable autocmds so if the extensions rely on BufReadCmd it works
          util.opts.with({ eventignore = "" }, function()
            util.try_log_else(
              extmod.load_win,
              { [1] = "Extension %s load_win error: %s", [2] = win.extension, notify = true },
              ---@param new_winid integer
              function(new_winid)
                new_winid = new_winid or win.winid
                win.winid = new_winid
              end,
              win.winid,
              win.extension_data
            )
          end)
        end
      elseif win.loclist_win then
        -- Keep track of loclist windows, we'll restore them later.
        loclist_wins[win.winid] = win
      else
        -- This force-restores the buffer, regardless of `in_win`
        local ctx = Buf.added(win.bufname, win.bufuuid)
        log.fmt_debug("Loading buffer %s (uuid: %s) in win %s", win.bufname, win.bufuuid, win.winid)
        vim.api.nvim_win_set_buf(win.winid, ctx.bufnr)
        if win.alt then
          -- Ensure altbuf is restored already in case user decides to switch immediately (or an autocmd causes the switch)
          Buf.added(buflist[win.alt] or win.alt --[[@as string]])
          vim.cmd.balt({
            vim.fn.fnameescape(buflist[win.alt] or win.alt --[[@as string]]),
          })
        end
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
      if win.loclists then
        util.try_log(
          restore_loclists,
          { "Failed to restore loclists for window %s: %s", win.winid },
          win.winid,
          win.loclists[1],
          win.loclists[2],
          buflist
        )
      end
      -- Keep a mapping of old to new window IDs because loclist windows in the snapshot reference the old ones.
      -- `or 0` to allow migration from older format.
      winid_old_new[win.old_winid or 0] = win.winid
      -- Keep track of the relative position of this window inside its frame. Necessary to because loclist
      -- windows are always appended to the referenced window, but the user might have moved it. We'll force
      -- the order of windows inside their frame later (this workaround breaks if they were not in the same frame though).
      win.frame_pos = frame_pos
      -- Also, keep track of all windows to restore dimensions when loclists windows have been created.
      all_wins[#all_wins + 1] = win
    else
      for pos, branch_or_leaf in ipairs(layout_inner[2]) do
        winlayout_inner(branch_or_leaf, pos)
      end
    end
  end

  -- Restore window contents
  winlayout_inner(layout, 1)

  -- Restore loclist windows.
  for locl_winid, locl_win in pairs(loclist_wins) do
    local ref_winid = winid_old_new[assert(locl_win.loclist_win)] -- "filewinid" of loclist win
    if ref_winid then
      vim.api.nvim_set_current_win(ref_winid) -- Ensure the associated window is focused
      util.opts.with({ eventignore = "" }, function()
        vim.cmd("lopen") -- Create loclist window between associated one and placeholder, we're switching focus to the new one here
      end)
      local new_winid = vim.api.nvim_get_current_win()
      vim.api.nvim_win_close(locl_winid, true) -- Remove the placeholder.
      locl_win.winid = new_winid -- We replaced the window, update winid
    end
  end
  -- Now that all windows have been created, we can restore frame order, options/dimensions and cursor pos.
  vim.iter(all_wins):each(restore_final)
  -- Make it somewhat explicit that we're modifying dicts in-place
  return layout, active_winid
end

--- Hackityhack jumplist restoration by abusing ShaDa in the absence
--- of a proper API. Does not allow entries referring to unnamed buffers.
--- Needs to be called in buffer restore logic, preferably as the absolute last step,
--- after the active buffer has finished restoring, to avoid interference.
---@param winid? WinID ID of the window to restore. Defaults to current one.
function M.restore_jumplist(winid)
  winid = winid or vim.api.nvim_get_current_win()
  log.fmt_trace("Restore jumplist called for winid %d", winid)

  if vim.w[winid].continuity_jumplist then
    ---@type [WinInfo.JumplistEntry[], integer]
    local jumplist = vim.w[winid].continuity_jumplist
    local jumps, backtrack = jumplist[1], jumplist[2]
    local cursor = vim.w[winid].continuity_win_cursor
    log.fmt_debug("Restoring jumplist for win %s", winid)

    util.opts.with({ eventignore = "all" }, function()
      -- This is the buf the window should display (the current one). We might need
      -- to perform a switcheroo to properly restore the jumplist in the intended order.
      local correct_buf, correct_alt ---@type integer?, integer?
      if backtrack > 0 then
        -- The position that we are trying to restore needs to be filled by the last item
        -- in the jumplist since it's going to be pushed up top.
        ---@type WinInfo.JumplistEntry
        local last_item = assert(jumps[#jumps])
        table.insert(jumps, #jumps - backtrack, jumps[#jumps])
        jumps[#jumps] = nil
        correct_buf = vim.api.nvim_win_get_buf(winid)
        correct_alt = get_alternate_buf(winid) --[[@as integer]]
        if vim.api.nvim_buf_get_name(correct_buf) ~= last_item[1] then
          log.debug(
            "Need to jump back to non-final jumplist entry, which is in a different buffer than the currently displayed one"
          )
          -- Don't need to force-restore buffer, this is a technicality
          local bufnr = vim.fn.bufadd(last_item[1] --[[@as string]])
          if not vim.api.nvim_buf_is_loaded(bufnr) then
            vim.fn.bufload(bufnr)
          end
          vim.api.nvim_win_set_buf(winid, bufnr)
        else
          log.debug(
            "Need to jump back to non-final jumplist entry, which is in the same buffer as the currently displayed one"
          )
          correct_buf = nil
        end
        -- Before restoring shada, ensure vim thinks we're at the last entry of the new jumplist
        -- Note: It can happen that the last entry is removed from the jumplist
        -- if we're right on it for some reason.
        util.try_log(vim.api.nvim_win_set_cursor, {
          [1] = "Failed to faithfully reproduce jumplist for win %s, some positions might be off: %s",
          [2] = winid,
          level = "warn",
        }, winid --[[@as integer]], { last_item[2] or 1, last_item[3] or 0 })
      end
      local shaja = util.shada.new()
      local now = os.time() - #jumps
      -- local bufs = {}
      vim.iter(ipairs(jumps)):each(function(i, jump)
        ---@cast jump WinInfo.JumplistEntry
        shaja:add_jump(jump[1], jump[2], jump[3], now + i)
        -- bufs[i] = jump[1]
      end)
      -- Ensure all items are actually restored by adding all necessary buffers (?)
      -- vim.iter(bufs):each(vim.fn.bufadd)
      vim.cmd.clearjumps()
      util.try_log(shaja.read, { "Failed to restore jumplist for win %s: %s", winid }, shaja)
      if backtrack > 0 then
        vim.cmd('exe "norm! ' .. tostring(backtrack) .. '\\<C-o>"')
      end
      if correct_buf then
        vim.api.nvim_win_set_buf(winid, correct_buf)
      end
      if correct_alt then
        vim.cmd.balt({ vim.fn.fnameescape(vim.api.nvim_buf_get_name(correct_alt)) })
      end
      util.try_log(vim.api.nvim_win_set_cursor, {
        [1] = "Failed to win cursor to wanted for winid %s, its position might be off: %s",
        [2] = winid,
        level = "warn",
      }, winid --[[@as integer]], cursor)
    end)
    vim.w[winid].continuity_jumplist = nil
  end
end

---@param layout WinLayout|false|nil
---@param scale_factor [number, number] Scaling factor for [width, height]
---@param buflist string[] Indexed buffer list, generated during save
---@return WinID? ID of the window that should have focus after session load
function M.set_winlayout(layout, scale_factor, buflist)
  if not layout or not layout[1] then
    return
  end
  local focused_winid
  layout = set_winlayout(layout)
  layout, focused_winid = set_winlayout_data(layout, scale_factor, buflist)
  return focused_winid
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

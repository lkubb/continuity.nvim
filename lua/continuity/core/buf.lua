local M = {}

local Config = require("continuity.config")
local util = require("continuity.util")

local lazy_require = util.lazy_require
local Ext = lazy_require("continuity.core.ext")
local log = lazy_require("continuity.log")

---@type boolean?
local seeded
local uuid_v4_template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"

local restore_group = vim.api.nvim_create_augroup("ContinuityBufferRestore", { clear = true })

--- Generate a UUID for a buffer.
--- They are used to keep track of unnamed buffers between sessions
--- and as a general identifier when preserving unwritten changes.
---@return continuity.BufUUID
function M.generate_uuid()
  if not seeded then
    math.randomseed(os.time())
    ---@diagnostic disable-next-line: unused
    seeded = true
  end
  local uuid = string.gsub(uuid_v4_template, "[xy]", function(c)
    local r = math.random()
    local v = c == "x" and math.floor(r * 0x10) or (math.floor(r * 0x4) + 8)
    return string.format("%x", v)
  end)
  return uuid
end

--- List all untitled buffers using bufnr and uuid.
---@return {buf: continuity.BufNr, uuid: continuity.BufUUID?}[]
local function list_untitled_buffers()
  local res = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf) == "" then
      table.insert(res, { buf = buf, uuid = vim.b[buf].continuity_uuid })
    end
  end
  return res
end

--- Ensure a specific buffer exists (represented by file path or UUID) and has any UUID.
--- File path: Ensure the file is loaded into a buffer and has any UUID. If it does not, assign it the specified one.
--- Unnamed: Ensure an unnamed buffer with the specified UUID exists. If not, create a new unnamed buffer and assign the specified UUID.
---@param name string The path of the buffer or the empty string ("") for unnamed buffers.
---@param uuid? continuity.BufUUID The UUID the buffer should have.
---@return integer The buffer ID of the specified buffer.
function M.managed(name, uuid)
  local bufnr
  if name ~= "" then
    bufnr = vim.fn.bufadd(name)
  else
    for _, buf in ipairs(list_untitled_buffers()) do
      if buf.uuid == uuid then
        bufnr = buf.buf
        break
      end
    end
    if not bufnr then
      bufnr = vim.fn.bufadd("")
    end
  end
  vim.b[bufnr].continuity_uuid = vim.b[bufnr].continuity_uuid or uuid or M.generate_uuid()
  return bufnr
end

---List all continuity-managed buffers.
---@return continuity.ManagedBufID[]
function M.list()
  local res = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.b[buf].continuity_uuid then
      table.insert(res, {
        buf = buf,
        name = vim.api.nvim_buf_get_name(buf),
        uuid = vim.b[buf].continuity_uuid,
      })
    end
  end
  return res
end

---List all continuity-managed buffers that were modified.
---@return continuity.ManagedBufID[]
function M.list_modified()
  local res = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    -- Only list buffers that are known to us. This funtion is called during save,
    -- a missing uuid means the buffer should not be saved at all
    if
      vim.b[buf].continuity_uuid
      and (vim.b[buf]._continuity_needs_restore or vim.bo[buf].modified)
    then
      local in_win = vim.fn.bufwinid(buf)
      table.insert(res, {
        buf = buf,
        name = vim.api.nvim_buf_get_name(buf),
        uuid = vim.b[buf].continuity_uuid,
        in_win = in_win > 0 and in_win or false,
      })
    end
  end
  return res
end

--- Restore cursor positions in buffers/windows if necessary. This is necessary
--- either when a buffer that was hidden when the session was saved is loaded into a window for the first time
--- or when on_buf_load plugins have changed the buffer contents dramatically
--- after the reload triggered by :edit, otherwise the cursor is already restored
--- in core.layout.set_winlayout_data.
---@param bufnr continuity.BufNr The number of the buffer in the currently active window.
---@param win_only? boolean Only restore window-specific cursor positions of the buffer (multiple windows, first one is already recovered)
local function restore_buf_cursor(bufnr, win_only)
  local last_pos
  local current_win
  if win_only and not vim.b[bufnr].continuity_last_win_pos then
    -- Sanity check, this should not be triggered
    return
  elseif not win_only and not vim.b[bufnr].continuity_last_win_pos then
    -- The buffer is restored for the first time and was hidden when session was saved
    last_pos = vim.b[bufnr].continuity_last_buffer_pos
    log.fmt_debug(
      "Buffer %s was not remembered in a window, restoring cursor from buf mark: %s",
      bufnr,
      last_pos
    )
  else
    -- The buffer was at least in one window when saved. If it's this one, restore
    -- its window-specific cursor position (there can be multiple).
    current_win = vim.api.nvim_get_current_win()
    last_pos = vim.b[bufnr].continuity_last_win_pos[tostring(current_win)]
    log.fmt_debug(
      "Trying to restore cursor for buf %s in win %s from saved win cursor pos: %s",
      bufnr,
      current_win,
      last_pos or "nil"
    )
    -- Cannot change individual fields, need to re-assign the whole table
    local temp_pos_table = vim.b[bufnr].continuity_last_win_pos
    temp_pos_table[tostring(current_win)] = nil
    vim.b[bufnr].continuity_last_win_pos = temp_pos_table
    if not last_pos or not vim.tbl_isempty(temp_pos_table) then
      -- Either 1) the buffer is loaded into a new window before all its other saved ones
      -- have been restored or 2) this is one of several windows to this buffer that need to be restored.
      log.fmt_debug(
        last_pos and "There are more saved windows besides %s for buffer %s"
          or "Not remembering this window (%s) for this buffer (%s), it's a new one before all old ones were restored",
        current_win,
        bufnr
      )
      -- Need to use WinEnter since switching between multiple windows to the same buffer
      -- does not trigger a BufEnter event.
      vim.api.nvim_create_autocmd("WinEnter", {
        desc = "Continuity: restore cursor position of buffer in saved window",
        callback = function(args)
          log.fmt_trace("WinEnter triggered for buf: %s", args)
          restore_buf_cursor(args.buf, true)
        end,
        buffer = bufnr,
        once = true,
      })
    end
  end
  if not last_pos then
    -- This should only happen if the buffer had multiple associated windows and we're opening
    -- another one before restoring all saved ones.
    return
  end
  if not current_win then
    current_win = vim.api.nvim_get_current_win()
  end
  -- Ensure the cursor has not been moved already, e.g. when restoring a saved buffer
  -- that is scrolled to via vim.lsp.util.show_document with focus=true. This would reset
  -- the wanted position to the last one instead, causing confusion.
  local cline, ccol = unpack(vim.api.nvim_win_get_cursor(current_win))
  if cline ~= 1 or ccol ~= 0 then
    -- TODO: Consider adding the saved position one step ahead of the current
    -- position of the jumplist via vim.fn.getjumplist/vim.fn.setjumplist.
    log.fmt_debug(
      "Not restoring cursor for buffer %s in window %s at %s because it has already been moved to (%s|%s)",
      bufnr,
      current_win or "nil",
      last_pos,
      cline or "nil",
      ccol or "nil"
    )
  else
    log.fmt_debug("Restoring cursor for buffer %s in window %s at %s", bufnr, current_win, last_pos)
    -- log.lazy_debug(function()
    --   return "current cursor pre-restore: "
    --     .. vim.inspect(vim.api.nvim_win_call(current_win, vim.fn.winsaveview))
    -- end)
    local ok, msg = pcall(vim.api.nvim_win_set_cursor, current_win, last_pos)
    if not ok then
      log.fmt_error(
        "Restoring cursor for buffer %s in window %s failed: %s",
        bufnr,
        current_win,
        msg
      )
    end
  end
  -- Ensure we break the chain of window-specific cursor recoveries once all windows
  -- have been visited
  if
    vim.b[bufnr].continuity_last_win_pos and vim.tbl_isempty(vim.b[bufnr].continuity_last_win_pos)
  then
    -- Clear the window-specific positions of this buffer since all have been applied
    vim.b[bufnr].continuity_last_win_pos = nil
  end
  -- The buffer pos is only relevant for buffers that were not in a window when saving,
  -- and from here on only window-specific cursor positions need to be recovered.
  vim.b[bufnr].continuity_last_buffer_pos = nil
end

--- Last step of buffer restoration, should be triggered by the final BufEnter event (:edit)
--- for regular buffers or be called directly for non-:editable buffers (unnamed ones).
--- Allows extensions to modify the final buffer contents and restores the cursor position (again).
---@param bufnr continuity.BufNr The buffer number to restore
---@param buf continuity.BufData The saved buffer information
---@param data continuity.SessionData The complete session data
local function finish_restore_buf(bufnr, buf, data)
  -- Save the last position of the cursor for buf_load plugins
  -- that change the buffer text, which can reset cursor position.
  -- set_winlayout_data also sets continuity_last_win_pos with window ids
  -- if the buffer was displayed when saving the session.
  -- Extensions can request default restoration by setting continuity_restore_last_pos on the buffer
  vim.b[bufnr].continuity_last_buffer_pos = buf.last_pos

  log.fmt_debug("Calling on_buf_load extensions")
  for ext_name in pairs(Config.extensions) do
    if data[ext_name] then
      local extmod = Ext.get(ext_name)
      if extmod and extmod.on_buf_load then
        log.fmt_trace(
          "Calling extension %s with bufnr %s and data %s",
          ext_name,
          bufnr,
          data[ext_name]
        )
        local ok, err = pcall(extmod.on_buf_load, bufnr, data[ext_name])
        if not ok then
          vim.notify(
            string.format("[continuity] Extension %s on_buf_load error: %s", ext_name, err),
            vim.log.levels.ERROR
          )
        end
      end
    end
  end

  if vim.b[bufnr].continuity_restore_last_pos then
    log.fmt_debug("Need to restore last cursor pos for buf %s", bufnr)
    vim.b[bufnr].continuity_restore_last_pos = nil
    -- Need to schedule this, otherwise it does not work for previously hidden buffers
    -- to restore from mark.
    vim.schedule(function()
      restore_buf_cursor(bufnr)
    end)
  end
end

---@type fun(bufnr: integer, buf: table<string,any>, data: table<string,any>)
local plan_restore

--- Restore a single buffer. This tries to to trigger necessary autocommands that have been
--- suppressed during session loading, then provides plugins the possibility to alter
--- the buffer in some way (e.g. recover unsaved changes) and finally initiates recovery
--- of the last cursor position when a) the buffer was not inside a window when saving or
--- b) on_buf_load plugins reenabled recovery after altering the contents.
---@param bufnr integer The number of the buffer to restore
---@param buf continuity.BufData The saved buffer metadata of the buffer to restore
---@param data continuity.SessionData The complete session data
local function restore_buf(bufnr, buf, data)
  if not vim.b[bufnr]._continuity_need_edit then
    -- prevent recursion in nvim <0.11: https://github.com/neovim/neovim/pull/29544
    return
  end
  vim.b[bufnr]._continuity_need_edit = nil
  -- This function reloads the buffer in order to trigger the proper AutoCmds
  -- by calling :edit. It doesn't work for unnamed buffers though.
  if vim.api.nvim_buf_get_name(bufnr) == "" then
    log.fmt_debug("Buffer %s is an unnamed one, skipping :edit. Triggering filetype.", bufnr)
    -- At least trigger FileType autocommands for unnamed buffers
    -- The order is backwards then though, usually it's [Syntax] > Filetype > BufEnter
    -- now it's BufEnter > [Syntax] > Filetype. Issue?
    vim.bo[bufnr].filetype = vim.bo[bufnr].filetype
    -- Don't forget to finish restoration since we don't trigger edit here (cursor, extensions)
    finish_restore_buf(bufnr, buf, data)
    return
  end
  log.fmt_debug("Triggering :edit for %s", buf)
  -- We cannot get this information reliably in any other way.
  -- Need to set shortmess += A when loading initially because the
  -- message cannot be suppressed (but bufload does not allow choice).
  -- If there is an existing swap file, the loaded buffer will use a different one,
  -- so we cannot query it via swapname.
  local swapcheck = vim.api.nvim_create_autocmd("SwapExists", {
    callback = function()
      log.fmt_debug("Existing swapfile for buf %s at %s", bufnr, vim.v.swapname)
      vim.b[bufnr]._continuity_swapfile = vim.v.swapname
      -- TODO: better swap handling via swapinfo() and taking continuity into account
    end,
    once = true,
    group = restore_group,
  })
  local finish_restore = vim.api.nvim_create_autocmd("BufEnter", {
    desc = "Continuity: complete setup of restored buffer (2)",
    callback = function(args)
      log.fmt_trace("BufEnter triggered again for: %s", args)
      -- Might have already been deleted, in which case this call fails
      local ok, res = pcall(vim.api.nvim_del_autocmd, swapcheck)
      if not ok then
        log.fmt_trace("Failed deleting swapcheck autocmd for buf %s: %s", args.buf, res)
      end
      finish_restore_buf(args.buf, buf, data)
    end,
    buffer = bufnr,
    once = true,
    nested = true,
    group = restore_group,
  })

  local current_win = vim.api.nvim_get_current_win()
  -- Schedule this to avoid issues with triggering nested AutoCmds (unsure if necessary)
  vim.schedule(function()
    -- Ensure the active window has not changed, otherwise reschedule restoration
    if vim.api.nvim_get_current_win() ~= current_win then
      log.fmt_debug("Failed :edit-ing buf %s: Active window changed, rescheduling", bufnr)
      for auname, autocmd in pairs({ swapcheck = swapcheck, finish_restore = finish_restore }) do
        local ok, res = pcall(vim.api.nvim_del_autocmd, autocmd)
        if not ok then
          log.fmt_debug("Failed deleting %s autocmd for buf %s: %s", auname, bufnr, res)
        end
      end
      plan_restore(bufnr, buf, data)
      return
    end
    local ok, err = pcall(vim.cmd.edit, { mods = { emsg_silent = true } })
    if not ok then
      log.fmt_error("Failed :edit-ing buf %s: %s", bufnr, err)
    end
  end)
end

--- Create the autocommand that re-:edits a buffer when it's first entered.
--- Required since events were suppressed when loading it initially, which breaks many extensions.
---@param bufnr integer The number of the buffer to schedule restoration for
---@param buf continuity.BufData The saved buffer metadata of the buffer to schedule restoration for
---@param data continuity.SessionData The complete session data
function plan_restore(bufnr, buf, data)
  vim.b[bufnr]._continuity_need_edit = true
  vim.api.nvim_create_autocmd("BufEnter", {
    desc = "Continuity: complete setup of restored buffer (1a)",
    callback = function(args)
      if vim.g._continuity_verylazy_done then
        log.fmt_trace("BufEnter triggered for buf %s, VeryLazy done for: %s", bufnr, args)
        restore_buf(bufnr, buf, data)
      else
        log.fmt_trace("BufEnter triggered for buf %s, waiting for VeryLazy for: %s", bufnr, args)
        vim.api.nvim_create_autocmd("User", {
          pattern = "VeryLazy",
          desc = "Continuity: complete setup of restored buffer (1b)",
          callback = function()
            log.fmt_trace("BufEnter triggered, VeryLazy done for: %s", args)
            restore_buf(bufnr, buf, data)
          end,
          once = true,
          nested = true,
          group = restore_group,
        })
      end
    end,
    buffer = bufnr,
    once = true,
    nested = true,
    group = restore_group,
  })
end

--- Ensure a saved buffer exists in the same state as it was saved.
--- Extracted from the loading logic to keep DRY.
--- This should be called when events are suppressed.
---@param buf continuity.BufData The saved buffer metadata for the buffer
---@param data continuity.SessionData The complete session data
---@return continuity.BufNr
function M.restore(buf, data)
  local bufnr = M.managed(buf.name, buf.uuid)

  if buf.loaded then
    vim.fn.bufload(bufnr)
    vim.b[bufnr].continuity_restore_last_pos = true
    plan_restore(bufnr, buf, data)
  end
  vim.b[bufnr].continuity_last_buffer_pos = buf.last_pos
  util.opts.restore_buf(bufnr, buf.options)
  return bufnr
end

return M

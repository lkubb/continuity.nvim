---@class continuity.core.buf
local M = {}

---@namespace continuity.core.buf
---@using continuity.core

local util = require("continuity.util")

local lazy_require = util.lazy_require
local Ext = lazy_require("continuity.core.ext")
local log = lazy_require("continuity.log")

---@type boolean?
local seeded
local uuid_v4_template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"

local restore_group = vim.api.nvim_create_augroup("ContinuityBufferRestore", { clear = true })

--- Lookup table for marks to ignore when saving/restoring buffer-local marks.
--- Most of these depend on the window (cursor) state, not the buffer (marked as WIN).
--- Some cannot be set from outside (RO).
--- Note: `[`, `<`, `>` and `]` can be set and are buffer-local.
---@type table<string, true?>
local IGNORE_LOCAL_MARKS = {
  ["'"] = true, -- previous context [WIN]
  ["`"] = true, -- previous context [WIN]
  ["{"] = true, -- move to start of current paragraph [WIN]
  ["}"] = true, -- move to end of current paragraph [WIN]
  ["("] = true, -- move to start of current sentence [WIN]
  [")"] = true, -- move to end of current sentence [WIN]
  ["."] = true, -- last change location [RO]
  ["^"] = true, -- last insert mode exit location [RO]
}

--- Generate a UUID for a buffer.
--- They are used to keep track of unnamed buffers between sessions
--- and as a general identifier when preserving unwritten changes.
---@return BufUUID
local function generate_uuid()
  if not seeded then
    math.randomseed(os.time())
    seeded = true
  end
  local uuid = string.gsub(uuid_v4_template, "[xy]", function(c)
    local r = math.random()
    local v = c == "x" and math.floor(r * 0x10) or (math.floor(r * 0x4) + 8)
    return string.format("%x", v)
  end)
  return uuid
end

--- Get a mapping of all buffer-local marks that can be restored.
--- Note: Ignores marks that depend on the window (like `'` and `}`) and read-only ones (`.`, `^`)
---@param ctx BufContext Buffer context to get local marks for
---@return table<string, AnonymousMark?> local_marks #
---   Mapping of mark name to (line, col) tuple, (1, 0)-indexed
function M.get_marks(ctx)
  if ctx.initialized == false then
    if not ctx.snapshot_data then
      log.fmt_error(
        "Internal error: Buffer %s not marked as initialized, but missing snapshot data.",
        tostring(ctx)
      )
    elseif ctx.snapshot_data.marks then
      -- We didn't restore the marks yet because the buffer was never focused in this session, so remember the data from last time
      return ctx.snapshot_data.marks
    end
    log.fmt_debug("Buffer %s not yet initialized, but did not remember marks", tostring(ctx))
  end
  return vim.iter(vim.fn.getmarklist(ctx.bufnr)):fold({}, function(acc, mark)
    local n = mark.mark:sub(2, 2)
    -- Cannot restore last change location mark, so filter it out.
    if not IGNORE_LOCAL_MARKS[n] then
      acc[mark.mark:sub(2, 2)] = { mark.pos[2], mark.pos[3] }
    end
    return acc
  end)
end

--- Get a list of changelist entries and the current changelist position (from most recent back).
--- Note that the changelist position can only be queried for buffers that are visible in a window.
---@param ctx BufContext Buffer context to get changelist for
---@return [Snapshot.BufData.ChangelistItem[], integer] changes_backtrack #
function M.parse_changelist(ctx)
  if ctx.initialized == false then
    if not ctx.snapshot_data then
      log.fmt_error(
        "Internal error: Buffer %s not marked as initialized, but missing snapshot data.",
        tostring(ctx)
      )
    elseif ctx.snapshot_data.changelist then
      -- We didn't restore the changelist yet because the buffer was never focused in this session, so remember the data from last time
      return ctx.snapshot_data.changelist
    end
    log.fmt_debug("Buffer %s not yet initialized, but did not remember changelist", tostring(ctx))
  end
  local changelist
  vim.api.nvim_buf_call(ctx.bufnr, function()
    -- Only current buffer has correct changelist position, for others getchangelist returns the length of the list.
    -- Additionally, the current buffer needs to be displayed in the current window. I think the window change
    -- happens automatically if the buffer is displayed in a window in the current tabpage (?).
    -- Effectively, this means that the current changelist position is only correctly preserved for visible buffers,
    -- others get reset to the most recent entry.
    -- TODO: Consider BufWinLeave AutoCmd to save this info if deemed relevant enough...
    changelist = vim.fn.getchangelist(ctx.bufnr)
  end)
  assert(#changelist == 2, "Internal error: requested changelist for nonexistent buffer")
  ---@cast changelist [[], integer]
  local changes, current_pos = changelist[1], changelist[2]
  local parsed = {}
  for _, change in ipairs(changes) do
    parsed[#parsed + 1] = { change.lnum or 1, change.col or 0 }
  end
  return { parsed, math.max(0, #parsed - current_pos - 1) }
end

local BufContext = {}

---@param bufnr BufNr Buffer number
---@return BufContext ctx #
function BufContext.new(bufnr)
  return setmetatable({ bufnr = bufnr }, BufContext)
end

---@param uuid BufUUID Buffer UUID
---@return BufContext? uuid_ctx Buffer context for buffer with `uuid`, if found
function BufContext.by_uuid(uuid)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if (vim.b[bufnr].continuity_ctx or {}).uuid == uuid then
      return BufContext.new(bufnr)
    end
  end
end

function BufContext.__index(self, key)
  if key == "name" then
    -- The name doesn't change, so we can save it on the context itself
    rawset(self, "name", vim.api.nvim_buf_get_name(self.bufnr))
    return self.name
  end
  return (vim.b[self.bufnr].continuity_ctx or {})[key]
end

function BufContext.__newindex(self, key, value)
  if key == "name" then
    error("Cannot set buffer name")
  end
  local cur = vim.b[self.bufnr].continuity_ctx or {}
  cur[key] = value
  vim.b[self.bufnr].continuity_ctx = cur
end

function BufContext:__tostring()
  return ("#%s (%s, UUID: %s)"):format(
    self.bufnr,
    self.name ~= "" and ('name: "%s"'):format(self.name) or "unnamed",
    self.uuid or "[not set yet]"
  )
end

--- Get continuity buffer context for a buffer (~ proxy to vim.b.continuity_ctx).
--- Keys can be updated in-place.
---@param bufnr? BufNr #
---   Buffer to get the context for. Defaults to the current buffer
---@param init? BufUUID #
---   Optionally enforce a specific buffer UUID. Errors if it's already set to something else.
---@return BufContext ctx #
function M.ctx(bufnr, init)
  local ctx = BufContext.new(bufnr or vim.api.nvim_get_current_buf())
  local current_uuid = ctx.uuid
  ---@diagnostic disable-next-line: unnecessary-if
  if current_uuid then
    if init and current_uuid ~= init then
      --- FIXME: If a named buffer already exists with a different uuid, this fails.
      ---        Shouldn't be a problem with global sessions, but might be with tab sessions.
      ---        Those are not really accounted for in the modified handling atm.
      log.fmt_error(
        "UUID collision for buffer %s (%s)! Expected to be empty or %s, but it is already set to %s.",
        ctx.bufnr,
        ctx.name,
        init,
        current_uuid
      )
      error(
        "Buffer UUID collision! Please restart neovim and reload the session. "
          .. "This might be caused by the same file path being referenced in multiple sessions."
      )
    end
    return ctx
  end
  ctx.uuid = init or generate_uuid()
  return ctx
end

--- Ensure a specific buffer exists in this neovim instance.
--- A buffer is represented by its name (usually file path), or a specific UUID for unnamed buffers.
--- When `name` is not the empty string, adds the corresponding buffer.
--- When `name` is the empty string and `uuid` is given, searches untitled buffers for this UUID. If not found, adds an empty one.
--- Always ensures a buffer has a UUID. If `uuid` is given, the returned buffer is ensured to match it.
--- If `name` is not empty and the buffer already has another UUID, errors.
---@param name string #
---   Path of the buffer or the empty string ("") for unnamed buffers.
---@param uuid? BufUUID
---   UUID the buffer should have.
---@return BufContext ctx #
---   Buffer context of the specified buffer.
function M.added(name, uuid)
  local bufnr
  if name == "" and uuid then
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if
        vim.api.nvim_buf_get_name(buf) == ""
        and vim.b[buf].continuity_ctx
        and vim.b[buf].continuity_ctx.uuid == uuid
      then
        bufnr = buf
        break
      end
    end
  end
  if not bufnr then
    bufnr = vim.fn.bufadd(name)
  end
  return M.ctx(bufnr, uuid) -- ensure the buffer has a UUID
end

--- Restore cursor positions in buffers/windows if necessary. This is necessary
--- either when a buffer that was hidden when the session was saved is loaded into a window for the first time
--- or when on_buf_load plugins have changed the buffer contents dramatically
--- after the reload triggered by :edit, otherwise the cursor is already restored
--- in core.layout.set_winlayout_data.
---@param ctx BufContext #
---   Buffer context for the buffer in the currently active window.
---@param win_only? boolean #
---   Only restore window-specific cursor positions of the buffer
---   (multiple windows, first one is already recovered)
local function restore_buf_cursor(ctx, win_only)
  local last_pos
  local current_win
  if win_only and not ctx.last_win_pos then
    -- Sanity check, this should not be triggered
    return
  elseif not win_only and not ctx.last_win_pos then
    -- The buffer is restored for the first time and was hidden when session was saved
    last_pos = ctx.last_buffer_pos
    log.fmt_debug(
      "Buffer %s was not remembered in a window, restoring cursor from buf mark: %s",
      tostring(ctx),
      last_pos
    )
  else
    ---@cast ctx.last_win_pos -nil
    -- The buffer was at least in one window when saved. If it's this one, restore
    -- its window-specific cursor position (there can be multiple).
    current_win = vim.api.nvim_get_current_win()
    last_pos = ctx.last_win_pos[tostring(current_win)]
    log.fmt_debug(
      "Trying to restore cursor for buf %s in win %s from saved win cursor pos: %s",
      tostring(ctx),
      current_win,
      last_pos or "nil"
    )
    -- Cannot change individual fields, need to re-assign the whole table
    local temp_pos_table = ctx.last_win_pos
    temp_pos_table[tostring(current_win)] = nil
    ctx.last_win_pos = temp_pos_table
    if not last_pos or not vim.tbl_isempty(temp_pos_table) then
      -- Either 1) the buffer is loaded into a new window before all its other saved ones
      -- have been restored or 2) this is one of several windows to this buffer that need to be restored.
      log.fmt_debug(
        last_pos and "There are more saved windows besides %s for buffer %s"
          or "Not remembering this window (%s) for this buffer (%s), it's a new one before all old ones were restored",
        current_win,
        tostring(ctx)
      )
      -- Need to use WinEnter since switching between multiple windows to the same buffer
      -- does not trigger a BufEnter event.
      vim.api.nvim_create_autocmd("WinEnter", {
        desc = "Continuity: restore cursor position of buffer in saved window",
        callback = function(args)
          log.fmt_trace("WinEnter triggered for buffer %s (args: %s)", tostring(ctx), args)
          restore_buf_cursor(ctx, true)
        end,
        buffer = ctx.bufnr,
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
    -- position of the jumplist
    log.fmt_debug(
      "Not restoring cursor for buffer %s in window %s at %s because it has already been moved to (%s|%s)",
      tostring(ctx),
      current_win or "nil",
      last_pos,
      cline or "nil",
      ccol or "nil"
    )
  else
    log.fmt_debug(
      "Restoring cursor for buffer %s in window %s at %s",
      tostring(ctx),
      current_win,
      last_pos
    )
    -- log.lazy_debug(function()
    --   return "current cursor pre-restore: "
    --     .. vim.inspect(vim.api.nvim_win_call(current_win, vim.fn.winsaveview))
    -- end)
    util.try_log(vim.api.nvim_win_set_cursor, {
      "Failed to restore cursor for buffer %s in window %s: %s",
      tostring(ctx),
      current_win,
    }, current_win, last_pos)
  end
  -- Ensure we break the chain of window-specific cursor recoveries once all windows
  -- have been visited
  if ctx.last_win_pos and vim.tbl_isempty(ctx.last_win_pos) then
    -- Clear the window-specific positions of this buffer since all have been applied
    ctx.last_win_pos = nil
  end
  -- The buffer pos is only relevant for buffers that were not in a window when saving,
  -- and from here on only window-specific cursor positions need to be recovered.
  ctx.last_buffer_pos = nil
end

--- Restore a single modified buffer when it is first focused in a window.
---@param ctx BufContext Buffer context for the buffer to restore.
local function restore_modified(ctx)
  log.fmt_trace("Restoring modified buffer %s", tostring(ctx))
  if not ctx.uuid then
    -- sanity check, should not hit
    log.fmt_error(
      "Not restoring buffer %s because it does not have an internal uuid set."
        .. " This is likely an internal error.",
      tostring(ctx)
    )
    return
  end
  if ctx.swapfile then
    if vim.bo[ctx.bufnr].readonly then
      ctx.unrestored = true
      -- Unnamed buffers should not have a swap file, but account for it anyways
      log.fmt_warn(
        "Not restoring buffer %s because it is read-only, likely because it has an "
          .. "existing swap file and you chose to open it read-only.",
        tostring(ctx)
      )
      return
    end
    -- TODO: Add some autodecide logic
    --
    -- if util.path.exists(ctx.swapfile) then
    --   local swapinfo = vim.fn.swapinfo(ctx.swapfile)
    -- end
  end
  local state_dir = assert(ctx.state_dir)
  local save_file = vim.fs.joinpath(state_dir, "modified_buffers", ctx.uuid .. ".buffer")
  if not util.path.exists(save_file) then
    ctx.needs_restore = nil
    log.fmt_warn("Not restoring buffer %s because its save file is missing.", tostring(ctx))
    return
  end
  log.fmt_debug("Loading buffer changes for buffer %s", tostring(ctx))
  util.try_log_else(util.path.read_lines, {
    "Failed loading buffer changes for %s: %s",
    ctx,
  }, function(file_lines)
    vim.api.nvim_buf_set_lines(ctx.bufnr, 0, -1, true, file_lines)
    -- Don't read the undo file if we're inside a recovered buffer, which should ensure the
    -- user can undo the recovery overwrite. This should be handled better.
    if not ctx.swapfile then
      local undo_file = vim.fs.joinpath(state_dir, "modified_buffers", ctx.uuid .. ".undo")
      log.fmt_debug("Loading undo history for buffer %s", tostring(ctx))
      util.try_log(
        vim.api.nvim_cmd,
        { "Failed to load undo history for buffer %s: %s", tostring(ctx) },
        { cmd = "rundo", args = { vim.fn.fnameescape(undo_file) }, mods = { silent = true } },
        {}
      )
    else
      log.warn(
        "Skipped loading undo history for buffer %s because it had a swapfile: %s",
        tostring(ctx),
        ctx.swapfile
      )
    end
    ctx.needs_restore = nil
    ctx.restore_last_pos = true
    ctx.last_changedtick = vim.b[ctx.bufnr].changedtick
  end, save_file)
  log.fmt_trace("Finished restoring modified buffer %s", ctx)
end

--- Last step of buffer restoration, should be triggered by the final BufEnter event (:edit)
--- for regular buffers or be called directly for non-:editable buffers (unnamed ones).
--- Allows extensions to modify the final buffer contents and restores the cursor position (again).
---@param ctx BufContext Buffer context for the buffer to restore
---@param buf Snapshot.BufData Saved buffer information
---@param data Snapshot Complete session data
local function finish_restore_buf(ctx, buf, data)
  -- Save the last position of the cursor for buf_load plugins
  -- that change the buffer text, which can reset cursor position.
  -- set_winlayout_data also sets continuity_last_win_pos with window ids
  -- if the buffer was displayed when saving the session.
  -- Extensions can request default restoration by setting continuity_restore_last_pos on the buffer
  ctx.last_buffer_pos = buf.last_pos

  if data.modified and data.modified[buf.uuid] then
    restore_modified(ctx)
  end

  local marks_cleared ---@type boolean?

  if ctx.name ~= "" and buf.changelist then
    local now = os.time() - #buf.changelist
    local change_shada = util.shada.new()
    vim.iter(ipairs(buf.changelist[1])):each(function(i, change)
      change_shada:add_change(ctx.name, change[1], change[2], now + i)
    end)
    -- There's no `:clearchanges`, need to clear all buffer-local marks.
    -- TODO: Restore them after
    _, marks_cleared = vim.cmd.delmarks({ bang = true }), true
    util.try_log(function()
      change_shada:read()
      if buf.changelist[2] > 0 then
        local prev = vim.api.nvim_win_get_cursor(0)
        vim.cmd("keepjumps norm! " .. tostring(buf.changelist[2] + 1) .. "g;")
        -- Need to keep position the same as before call, cannot rely on restore_last_pos logic
        -- because it intentionally skips setting the cursor if it's anywhere other than (1, 0)
        vim.api.nvim_win_set_cursor(0, prev)
        ctx.restore_last_pos = true
      end
    end, { "Failed to restore changelist for buffer %s: %s", tostring(ctx) }, change_shada)
  end

  if buf.marks then
    if not marks_cleared then
      -- Cannot do delmarks!, which also clears jumplist (that isn't tracked/restored since we're here)
      for _, mark in ipairs(vim.fn.getmarklist(ctx.bufnr)) do
        -- TODO: Really clear all marks?
        vim.api.nvim_buf_del_mark(ctx.bufnr, mark.mark:sub(2, 2))
      end
    end
    for mark, pos in pairs(buf.marks) do
      if not IGNORE_LOCAL_MARKS[mark] then
        util.try_log(
          vim.api.nvim_buf_set_mark,
          { "Failed setting mark %s for buf %s: %s", mark, tostring(ctx) },
          ctx.bufnr,
          mark,
          pos[1],
          pos[2],
          {}
        )
      end
    end
  end

  log.fmt_debug("Calling on_buf_load extensions")
  Ext.call("on_buf_load", data, ctx.bufnr)

  if ctx.restore_last_pos then
    log.fmt_debug("Need to restore last cursor pos for buf %s", tostring(ctx))
    ctx.restore_last_pos = nil
    -- Need to schedule this, otherwise it does not work for previously hidden buffers
    -- to restore from mark.
    vim.schedule(function()
      restore_buf_cursor(ctx)
      ctx.initialized, ctx.snapshot_data = true, nil
    end)
  else
    vim.schedule(function()
      ctx.initialized, ctx.snapshot_data = true, nil
    end)
  end
end

---@type fun(ctx: BufContext, buf: table<string,any>, data: table<string,any>)
local plan_restore

--- Restore a single buffer. This tries to to trigger necessary autocommands that have been
--- suppressed during session loading, then provides plugins the possibility to alter
--- the buffer in some way (e.g. recover unsaved changes) and finally initiates recovery
--- of the last cursor position when a) the buffer was not inside a window when saving or
--- b) on_buf_load plugins reenabled recovery after altering the contents.
---@param ctx BufContext Buffer context for the buffer to restore
---@param buf Snapshot.BufData Saved buffer metadata of the buffer to restore
---@param data Snapshot Complete session data
local function restore_buf(ctx, buf, data)
  if not ctx.need_edit then
    -- prevent recursion in nvim <0.11: https://github.com/neovim/neovim/pull/29544
    return
  end
  ctx.need_edit = nil
  -- This function reloads the buffer in order to trigger the proper AutoCmds
  -- by calling :edit. It doesn't work for unnamed buffers though.
  if ctx.name == "" then
    log.fmt_debug(
      "Buffer %s is an unnamed one, skipping :edit. Triggering filetype.",
      tostring(ctx)
    )
    -- At least trigger FileType autocommands for unnamed buffers
    -- The order is backwards then though, usually it's [Syntax] > Filetype > BufEnter
    -- now it's BufEnter > [Syntax] > Filetype. Issue?
    vim.bo[ctx.bufnr].filetype = vim.bo[ctx.bufnr].filetype
    -- Don't forget to finish restoration since we don't trigger edit here (cursor, extensions)
    finish_restore_buf(ctx, buf, data)
    return
  end
  log.fmt_debug("Triggering :edit for %s", tostring(ctx))
  -- We cannot get this information reliably in any other way.
  -- Need to set shortmess += A when loading initially because the
  -- message cannot be suppressed (but bufload does not allow choice).
  -- If there is an existing swap file, the loaded buffer will use a different one,
  -- so we cannot query it via swapname.
  local swapcheck = vim.api.nvim_create_autocmd("SwapExists", {
    callback = function()
      log.fmt_debug("Existing swapfile for buf %s at %s", tostring(ctx), vim.v.swapname)
      ctx.swapfile = vim.v.swapname
      -- TODO: better swap handling via swapinfo() and taking modified buffers into account
    end,
    once = true,
    group = restore_group,
  })
  local finish_restore = vim.api.nvim_create_autocmd("BufEnter", {
    desc = "Continuity: complete setup of restored buffer (2)",
    callback = function(args)
      log.fmt_trace("BufEnter triggered again for buffer %s (event args: %s)", tostring(ctx), args)
      -- Might have already been deleted, in which case this call fails
      util.try_log(vim.api.nvim_del_autocmd, {
        [1] = "Failed to delete swapcheck autocmd for buffer %s: %s",
        [2] = tostring(ctx),
        level = "trace",
      }, swapcheck)
      util.try_log(
        finish_restore_buf,
        { "Failed final buffer restoration for buffer %s! Error: %s", tostring(ctx) },
        ctx,
        buf,
        data
      )
      -- Should be called last. Avoid overhead by pre-checking if the logic needs to run at all.
      if vim.w.continuity_jumplist then
        require("continuity.core.layout").restore_jumplist()
      end
    end,
    buffer = ctx.bufnr,
    once = true,
    nested = true,
    group = restore_group,
  })

  local current_win = vim.api.nvim_get_current_win()
  -- Schedule this to avoid issues with triggering nested AutoCmds (unsure if necessary)
  vim.schedule(function()
    -- Ensure the active window has not changed, otherwise reschedule restoration
    if vim.api.nvim_get_current_win() ~= current_win then
      log.fmt_debug(
        "Failed :edit-ing buffer %s: Active window changed, rescheduling",
        tostring(ctx)
      )
      for auname, autocmd in pairs({ swapcheck = swapcheck, finish_restore = finish_restore }) do
        util.try_log(vim.api.nvim_del_autocmd, {
          [1] = "Failed to delete %s autocmd for buffer %s: %s",
          [2] = auname,
          [3] = tostring(ctx),
          level = "debug",
        }, autocmd)
      end
      plan_restore(ctx, buf, data)
      return
    end
    -- We need to `keepjumps`, otherwise we reset our jumplist position here/add/move an entry
    util.try_log(
      vim.cmd.edit,
      { "Failed to :edit buffer %s: %s", tostring(ctx) },
      { mods = { emsg_silent = true, keepjumps = true } }
    )
  end)
end

--- Create the autocommand that re-:edits a buffer when it's first entered.
--- Required since events were suppressed when loading it initially, which breaks many extensions.
---@param ctx BufContext Buffer context for the buffer to schedule restoration for
---@param buf Snapshot.BufData Saved buffer metadata of the buffer to schedule restoration for
---@param data Snapshot Complete session data
function plan_restore(ctx, buf, data)
  ctx.need_edit = true
  vim.api.nvim_create_autocmd("BufEnter", {
    desc = "Continuity: complete setup of restored buffer (1a)",
    callback = function(args)
      if vim.g._continuity_verylazy_done then
        log.fmt_trace(
          "BufEnter triggered for buffer %s (args: %s), VeryLazy done",
          tostring(ctx),
          args
        )
        restore_buf(ctx, buf, data)
      else
        log.fmt_trace(
          "BufEnter triggered for buffer %s (args: %s), waiting for VeryLazy",
          tostring(ctx),
          args
        )
        vim.api.nvim_create_autocmd("User", {
          pattern = "VeryLazy",
          desc = "Continuity: complete setup of restored buffer (1b)",
          callback = function()
            log.fmt_trace("BufEnter triggered, VeryLazy done for: %s (%s)", tostring(ctx), args)
            restore_buf(ctx, buf, data)
          end,
          once = true,
          nested = true,
          group = restore_group,
        })
      end
    end,
    buffer = ctx.bufnr,
    once = true,
    nested = true,
    group = restore_group,
  })
end

--- Called for buffers with persisted unsaved modifications.
--- Ensures buffer previews (like in pickers) show the correct text.
---@param ctx BufContext Buffer context for the buffer to restore modifications for
---@param state_dir string Directory unwritten buffer modifications are persisted to
local function restore_modified_preview(ctx, state_dir)
  local save_file = vim.fs.joinpath(state_dir, "modified_buffers", ctx.uuid .. ".buffer")
  util.try_log_else(
    util.path.read_lines,
    {
      [1] = "Not restoring buffer %s because its save file could not be read: %s",
      [2] = tostring(ctx),
      level = "warn",
    },
    ---@param file_lines string[]
    function(file_lines)
      log.fmt_debug("Restoring modified buffer %s", ctx)
      vim.api.nvim_buf_set_lines(ctx.bufnr, 0, -1, true, file_lines)
      -- Ensure autocmd :edit works. It will trigger the final restoration.
      -- Don't do it for unnamed buffers since :edit cannot be called for them.
      if ctx.name ~= "" then
        vim.bo[ctx.bufnr].modified = false
      end
      -- Ensure the buffer is remembered as only partially restored if it is never loaded until the next save
      ctx.needs_restore = true
      -- Remember the state dir for restore_modified, which is called after a buffer has been re-edited
      ctx.state_dir = state_dir
    end,
    save_file
  )
end

--- Ensure a saved buffer exists in the same state as it was saved.
--- Extracted from the loading logic to keep DRY.
--- This should be called while events are suppressed.
---@param buf Snapshot.BufData Saved buffer metadata for the buffer
---@param data Snapshot Complete session data
---@param state_dir? string Directory unwritten buffer modifications are persisted to
---@return BufNr bufnr Buffer number of the restored buffer
function M.restore(buf, data, state_dir)
  local ctx = M.added(buf.name, buf.uuid)
  if ctx.initialized ~= nil then
    -- TODO: Consider the effect of multiple snapshots referencing the same buffer without `reset`
    log.fmt_warn("core.buf.restore called more than once for buffer %s, ignoring.", tostring(ctx))
    return ctx.bufnr
  end

  ctx.initialized = not buf.loaded -- unloaded bufs don't need any further initialization
  if buf.loaded then
    vim.fn.bufload(ctx.bufnr)
    ctx.restore_last_pos = true
    ctx.snapshot_data = buf -- this can be a large table when changelists are stored, problem?
    -- FIXME: All autocmds are added to the same, global augroup. When detaching a session with reset,
    --        the corresponding aucmds (and maybe continuity context) should likely be cleared though.
    plan_restore(ctx, buf, data)
  end
  ctx.last_buffer_pos = buf.last_pos
  util.opts.restore_buf(ctx.bufnr, buf.options)
  if state_dir and data.modified and data.modified[buf.uuid] then
    restore_modified_preview(ctx, state_dir)
  end
  return ctx.bufnr
end

--- Remove previously saved buffers and their undo history when they are
--- no longer part of Continuity's state (most likely have been written).
---@param state_dir string #
---   Path to the modified_buffers directory of the session represented by `data`.
---@param keep table<BufUUID, true?> #
---   Buffers to keep saved modifications for
function M.clean_modified(state_dir, keep)
  local remembered_buffers =
    vim.fn.glob(vim.fs.joinpath(state_dir, "modified_buffers", "*.buffer"), true, true)
  for _, sav in ipairs(remembered_buffers) do
    local uuid = vim.fn.fnamemodify(sav, ":t:r")
    if not keep[uuid] then
      pcall(vim.fn.delete, sav)
      pcall(vim.fn.delete, vim.fn.fnamemodify(sav, ":r") .. ".undo")
      local ctx = BufContext.by_uuid(uuid)
      if ctx then
        ctx.last_changedtick = nil
      end
    end
  end
end

--- Iterate over modified buffers, save them and their undo history
--- and return session data.
---@param state_dir string Directory unwritten buffer modifications are persisted to
---@param bufs BufContext[] List of buffers to check for modifications.
---@return table<BufUUID, true?>? #
---   Lookup table of Buffer UUID for modification status
function M.save_modified(state_dir, bufs)
  local modified_buffers = vim.tbl_filter(function(buf)
    -- Ensure buffers with pending modifications (never focused after a session was restored)
    -- are included in the list of modified buffers. Saving them is skipped later.
    return buf.needs_restore or vim.bo[buf.bufnr].modified
  end, bufs)
  log.fmt_debug(
    "Saving modified buffers in state dir (%s)\nModified buffers: %s",
    state_dir,
    modified_buffers
  )

  -- We don't need to mkdir the state dir since write_file does that automatically
  ---@type table<BufUUID, true?>
  local res = {}
  -- Can't call :wundo when the cmd window (e.g. q:) is active, otherwise we receive
  -- E11: Invalid in command-line window
  -- TODO: Should we save modified buffers at all if we can't guarantee undo history?
  ---@type boolean
  local skip_wundo = vim.fn.getcmdwintype() ~= ""
  for _, ctx in ipairs(modified_buffers) do
    -- Unrestored buffers should not overwrite the save file, but still be remembered
    -- unrestored are buffers that were not restored at all due to swapfile and being opened read-only
    -- needs_restore are buffers that were restored initially, but have never been entered since loading.
    -- If we saved the latter, we would lose the undo history since it hasn't been loaded for them.
    -- This at least affects unnamed buffers since we solely manage the history for them.
    if ctx.unrestored or ctx.needs_restore then
      log.fmt_debug("Modified buf %s has not been restored yet, skipping save", tostring(ctx))
    else
      local save_file = vim.fs.joinpath(state_dir, "modified_buffers", ctx.uuid .. ".buffer")
      local undo_file = vim.fs.joinpath(state_dir, "modified_buffers", ctx.uuid .. ".undo")
      if
        ctx.last_changedtick
        and ctx.last_changedtick == vim.b[ctx.bufnr].changedtick
        and util.path.exists(save_file)
        and (skip_wundo or util.path.exists(undo_file))
      then
        log.fmt_debug(
          "Modified buf %s has not changed since last save, skipping save",
          tostring(ctx)
        )
      else
        log.fmt_debug("Saving modified buffer %s to %s", tostring(ctx), save_file)
        util.try_log(function()
          -- Backup the current buffer contents. Avoid vim.cmd.w because that can have side effects, even with keepalt/noautocmd.
          local lines = vim.api.nvim_buf_get_text(ctx.bufnr, 0, 0, -1, -1, {})
          util.path.write_file(save_file, table.concat(lines, "\n") .. "\n")
          -- TODO: Consider ways to optimize this/make it more robust:
          -- * Save hash of on-disk state
          -- * Save patch only

          if not skip_wundo then
            vim.api.nvim_buf_call(ctx.bufnr, function()
              vim.cmd.wundo({
                vim.fn.fnameescape(undo_file),
                bang = true,
                mods = { noautocmd = true, silent = true },
              })
              ctx.last_changedtick = vim.b[ctx.bufnr].changedtick
            end)
          else
            log.fmt_warn(
              "Need to skip backing up undo history for modified buffer %s to %s because cmd window is active",
              tostring(ctx),
              undo_file
            )
          end
        end, {
          "Error while saving modified buffer %s: %s",
          tostring(ctx),
        })
      end
    end
    res[ctx.uuid] = true
  end
  -- Clean up any remembered buffers that have been removed from the session
  -- or have been saved in the meantime. We can do that after completing the save.
  vim.schedule(function()
    M.clean_modified(state_dir, res)
  end)
  return res
end

return M

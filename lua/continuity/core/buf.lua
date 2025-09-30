---@class continuity.core.buf
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
local function generate_uuid()
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

local BufContext = {}

---@param bufnr continuity.BufNr?
---@return continuity.BufContext
function BufContext.new(bufnr)
  return setmetatable({ bufnr = bufnr }, BufContext)
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

--- Get continuity buffer context for a buffer (~ proxy to vim.b.continuity_ctx). Keys can be updated in-place.
---@param bufnr continuity.BufNr? The buffer to get the context for. Defaults to the current buffer
---@param init continuity.BufUUID? Optionally enforce a specific buffer UUID. Errors if it's already set to something else.
---@return continuity.BufContext
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
---@param name string The path of the buffer or the empty string ("") for unnamed buffers.
---@param uuid? continuity.BufUUID The UUID the buffer should have.
---@return continuity.BufContext The buffer context of the specified buffer.
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
---@param ctx continuity.BufContext The buffer context for the buffer in the currently active window.
---@param win_only? boolean Only restore window-specific cursor positions of the buffer (multiple windows, first one is already recovered)
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
      ctx.bufnr,
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
      ctx.bufnr,
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
        ctx.bufnr
      )
      -- Need to use WinEnter since switching between multiple windows to the same buffer
      -- does not trigger a BufEnter event.
      vim.api.nvim_create_autocmd("WinEnter", {
        desc = "Continuity: restore cursor position of buffer in saved window",
        callback = function(args)
          log.fmt_trace("WinEnter triggered for buf: %s", args)
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
    -- position of the jumplist via vim.fn.getjumplist/vim.fn.setjumplist.
    log.fmt_debug(
      "Not restoring cursor for buffer %s in window %s at %s because it has already been moved to (%s|%s)",
      ctx.bufnr,
      current_win or "nil",
      last_pos,
      cline or "nil",
      ccol or "nil"
    )
  else
    log.fmt_debug(
      "Restoring cursor for buffer %s in window %s at %s",
      ctx.bufnr,
      current_win,
      last_pos
    )
    -- log.lazy_debug(function()
    --   return "current cursor pre-restore: "
    --     .. vim.inspect(vim.api.nvim_win_call(current_win, vim.fn.winsaveview))
    -- end)
    local ok, msg = pcall(vim.api.nvim_win_set_cursor, current_win, last_pos)
    if not ok then
      log.fmt_error(
        "Restoring cursor for buffer %s in window %s failed: %s",
        ctx.bufnr,
        current_win,
        msg
      )
    end
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

---Restore a single modified buffer when it is first focused in a window.
---@param ctx continuity.BufContext The buffer context for the buffer to restore.
local function restore_modified(ctx)
  log.fmt_trace("Restoring modified buffer %s", ctx.bufnr)
  if not ctx.uuid then
    -- sanity check, should not hit
    log.fmt_error(
      "Not restoring '%s' because it does not have an internal uuid set."
        .. " This is likely an internal error.",
      ctx.name ~= "" and ctx.name or "unnamed buffer"
    )
    return
  end
  if ctx.swapfile then
    if vim.bo[ctx.bufnr].readonly then
      ctx.unrestored = true
      -- Unnamed buffers should not have a swap file, but account for it anyways
      log.fmt_warn(
        "Not restoring %s because it is read-only, likely because it has an "
          .. "existing swap file and you chose to open it read-only.",
        ctx.name ~= "" and ctx.name or ("unnamed buffer with uuid " .. ctx.uuid)
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
    log.fmt_warn(
      "Not restoring %s because its save file is missing.",
      ctx.name ~= "" and ctx.name or ("unnamed buffer with uuid " .. ctx.uuid)
    )
    return
  end
  log.fmt_debug("Loading buffer changes for buffer %s", ctx.uuid, ctx.bufnr)
  local ok, file_lines = pcall(util.path.read_lines, save_file)
  if ok then
    ---@cast file_lines -string
    log.fmt_debug("Loaded buffer changes for buffer %s, loading into %s", ctx.uuid, ctx.bufnr)
    vim.api.nvim_buf_set_lines(ctx.bufnr, 0, -1, true, file_lines)
    -- Don't read the undo file if we're inside a recovered buffer, which should ensure the
    -- user can undo the recovery overwrite. This should be handled better.
    if not ctx.swapfile then
      local undo_file = vim.fs.joinpath(state_dir, "modified_buffers", ctx.uuid .. ".undo")
      log.fmt_debug("Loading undo history for buffer %s", ctx.uuid)
      local err
      ok, err = pcall(
        vim.api.nvim_cmd,
        { cmd = "rundo", args = { undo_file }, mods = { silent = true } },
        {}
      )
      if not ok then
        log.fmt_error("Failed loading undo history for buffer %s: %s", ctx.uuid, err)
      end
    else
      log.warn(
        "Skipped loading undo history for buffer %s because it had a swapfile: %s",
        ctx.uuid,
        ctx.swapfile
      )
    end
    ctx.needs_restore = nil
    ctx.restore_last_pos = true
  end
  log.fmt_trace("Finished restoring modified buffer %s into %s", ctx.uuid, ctx.bufnr)
end

--- Last step of buffer restoration, should be triggered by the final BufEnter event (:edit)
--- for regular buffers or be called directly for non-:editable buffers (unnamed ones).
--- Allows extensions to modify the final buffer contents and restores the cursor position (again).
---@param ctx continuity.BufContext The buffer context for the buffer to restore
---@param buf continuity.BufData The saved buffer information
---@param data continuity.Snapshot The complete session data
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

  log.fmt_debug("Calling on_buf_load extensions")
  for ext_name in pairs(Config.extensions) do
    if data[ext_name] then
      local extmod = Ext.get(ext_name)
      if extmod and extmod.on_buf_load then
        log.fmt_trace(
          "Calling extension %s with bufnr %s and data %s",
          ext_name,
          ctx.bufnr,
          data[ext_name]
        )
        local ok, err = pcall(extmod.on_buf_load, ctx.bufnr, data[ext_name])
        if not ok then
          vim.notify(
            string.format("[continuity] Extension %s on_buf_load error: %s", ext_name, err),
            vim.log.levels.ERROR
          )
        end
      end
    end
  end

  if ctx.restore_last_pos then
    log.fmt_debug("Need to restore last cursor pos for buf %s", ctx.bufnr)
    ctx.restore_last_pos = nil
    -- Need to schedule this, otherwise it does not work for previously hidden buffers
    -- to restore from mark.
    vim.schedule(function()
      restore_buf_cursor(ctx)
    end)
  end
end

---@type fun(ctx: continuity.BufContext, buf: table<string,any>, data: table<string,any>)
local plan_restore

--- Restore a single buffer. This tries to to trigger necessary autocommands that have been
--- suppressed during session loading, then provides plugins the possibility to alter
--- the buffer in some way (e.g. recover unsaved changes) and finally initiates recovery
--- of the last cursor position when a) the buffer was not inside a window when saving or
--- b) on_buf_load plugins reenabled recovery after altering the contents.
---@param ctx continuity.BufContext The buffer context for the buffer to restore
---@param buf continuity.BufData The saved buffer metadata of the buffer to restore
---@param data continuity.Snapshot The complete session data
local function restore_buf(ctx, buf, data)
  if not ctx.need_edit then
    -- prevent recursion in nvim <0.11: https://github.com/neovim/neovim/pull/29544
    return
  end
  ctx.need_edit = nil
  -- This function reloads the buffer in order to trigger the proper AutoCmds
  -- by calling :edit. It doesn't work for unnamed buffers though.
  if ctx.name == "" then
    log.fmt_debug("Buffer %s is an unnamed one, skipping :edit. Triggering filetype.", ctx.bufnr)
    -- At least trigger FileType autocommands for unnamed buffers
    -- The order is backwards then though, usually it's [Syntax] > Filetype > BufEnter
    -- now it's BufEnter > [Syntax] > Filetype. Issue?
    vim.bo[ctx.bufnr].filetype = vim.bo[ctx.bufnr].filetype
    -- Don't forget to finish restoration since we don't trigger edit here (cursor, extensions)
    finish_restore_buf(ctx, buf, data)
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
      log.fmt_debug("Existing swapfile for buf %s at %s", ctx.bufnr, vim.v.swapname)
      ctx.swapfile = vim.v.swapname
      -- TODO: better swap handling via swapinfo() and taking modified buffers into account
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
      finish_restore_buf(ctx, buf, data)
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
      log.fmt_debug("Failed :edit-ing buf %s: Active window changed, rescheduling", ctx.bufnr)
      for auname, autocmd in pairs({ swapcheck = swapcheck, finish_restore = finish_restore }) do
        local ok, res = pcall(vim.api.nvim_del_autocmd, autocmd)
        if not ok then
          log.fmt_debug("Failed deleting %s autocmd for buf %s: %s", auname, ctx.bufnr, res)
        end
      end
      plan_restore(ctx, buf, data)
      return
    end
    local ok, err = pcall(vim.cmd.edit, { mods = { emsg_silent = true } })
    if not ok then
      log.fmt_error("Failed :edit-ing buf %s: %s", ctx.bufnr, err)
    end
  end)
end

--- Create the autocommand that re-:edits a buffer when it's first entered.
--- Required since events were suppressed when loading it initially, which breaks many extensions.
---@param ctx continuity.BufContext The buffer context for the buffer to schedule restoration for
---@param buf continuity.BufData The saved buffer metadata of the buffer to schedule restoration for
---@param data continuity.Snapshot The complete session data
function plan_restore(ctx, buf, data)
  ctx.need_edit = true
  vim.api.nvim_create_autocmd("BufEnter", {
    desc = "Continuity: complete setup of restored buffer (1a)",
    callback = function(args)
      if vim.g._continuity_verylazy_done then
        log.fmt_trace("BufEnter triggered for buf %s, VeryLazy done for: %s", ctx.bufnr, args)
        restore_buf(ctx, buf, data)
      else
        log.fmt_trace(
          "BufEnter triggered for buf %s, waiting for VeryLazy for: %s",
          ctx.bufnr,
          args
        )
        vim.api.nvim_create_autocmd("User", {
          pattern = "VeryLazy",
          desc = "Continuity: complete setup of restored buffer (1b)",
          callback = function()
            log.fmt_trace("BufEnter triggered, VeryLazy done for: %s", args)
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

---@param ctx continuity.BufContext
---@param state_dir string
local function restore_modified_preview(ctx, state_dir)
  local save_file = vim.fs.joinpath(state_dir, "modified_buffers", ctx.uuid .. ".buffer")
  local ok, file_lines = pcall(util.path.read_lines, save_file)
  if not ok then
    log.fmt_warn(
      "Not restoring %s because its save file could not be read: %s",
      ctx.uuid,
      file_lines
    )
  else
    ---@cast file_lines -string
    log.fmt_debug("Restoring modified buf %s into bufnr %s", ctx.uuid, ctx.bufnr)
    ---@diagnostic disable-next-line: unnecessary-if
    vim.api.nvim_buf_set_lines(ctx.bufnr, 0, -1, true, file_lines)
    -- Ensure autocmd :edit works. It will trigger the final restoration.
    -- Don't do it for unnamed buffers since :edit cannot be called for them.
    if ctx.name ~= "" then
      vim.bo[ctx.bufnr].modified = false
    end
    -- Ensure the buffer is remembered as modified if it is never loaded until the next save
    ctx.needs_restore = true
    -- Remember the state dir for restore_modified, which is called after a buffer has been re-edited
    ctx.state_dir = state_dir
  end
end

--- Ensure a saved buffer exists in the same state as it was saved.
--- Extracted from the loading logic to keep DRY.
--- This should be called when events are suppressed.
---@param buf continuity.BufData The saved buffer metadata for the buffer
---@param data continuity.Snapshot The complete session data
---@param state_dir string? The directory where unsaved buffers are persisted to
---@return continuity.BufNr
function M.restore(buf, data, state_dir)
  local ctx = M.added(buf.name, buf.uuid)

  if buf.loaded then
    vim.fn.bufload(ctx.bufnr)
    ctx.restore_last_pos = true
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

---Remove previously saved buffers and their undo history when they are
---no longer part of Continuity's state (most likely have been written).
---@param state_dir string The path to the modified_buffers directory of the session represented by `data`.
---@param keep table<continuity.BufUUID, true?> Buffers to keep saved modifications for
function M.clean_modified(state_dir, keep)
  local remembered_buffers =
    vim.fn.glob(vim.fs.joinpath(state_dir, "modified_buffers", "*.buffer"), true, true)
  for _, sav in ipairs(remembered_buffers) do
    local uuid = vim.fn.fnamemodify(sav, ":t:r")
    if not keep[uuid] then
      pcall(vim.fn.delete, sav)
      pcall(vim.fn.delete, vim.fn.fnamemodify(sav, ":r") .. ".undo")
    end
  end
end

---Iterate over modified buffers, save them and their undo history
---and return session data.
---@param state_dir string
---@param bufs continuity.BufContext[] List of buffers to check for modifications.
---@return table<continuity.ManagedBufID, true?>?
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
    if not (ctx.unrestored or ctx.needs_restore) then
      local save_file = vim.fs.joinpath(state_dir, "modified_buffers", ctx.uuid .. ".buffer")
      local undo_file = vim.fs.joinpath(state_dir, "modified_buffers", ctx.uuid .. ".undo")
      log.fmt_debug(
        "Saving modified buffer %s (%s) named '%s' to %s",
        ctx.bufnr,
        ctx.uuid,
        ctx.name,
        save_file
      )

      local ok, msg = pcall(function()
        -- Backup the current buffer contents. Avoid vim.cmd.w because that can have side effects, even with keepalt/noautocmd.
        local lines = vim.api.nvim_buf_get_text(ctx.bufnr, 0, 0, -1, -1, {})
        util.path.write_file(save_file, table.concat(lines, "\n") .. "\n")

        if not skip_wundo then
          vim.api.nvim_buf_call(ctx.bufnr, function()
            vim.cmd.wundo({ undo_file, bang = true, mods = { noautocmd = true, silent = true } })
          end)
        else
          log.fmt_warn(
            "Need to skip backing up undo history for modified buffer %s (%s) named '%s' to %s because cmd window is active",
            ctx.bufnr,
            ctx.uuid,
            ctx.name,
            undo_file
          )
        end
      end)
      if not ok then
        log.fmt_error(
          "Error saving modified buffer %s (%s) named '%s': %s",
          ctx.bufnr,
          ctx.uuid,
          ctx.name,
          msg
        )
      end
    else
      log.fmt_debug(
        "Modified buf %s (%s) named '%s' has not been restored yet, skipping save",
        ctx.bufnr,
        ctx.uuid,
        ctx.name
      )
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

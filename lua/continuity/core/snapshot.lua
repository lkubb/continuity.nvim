local Config = require("continuity.config")
local util = require("continuity.util")

local lazy_require = util.lazy_require
local Buf = lazy_require("continuity.core.buf")
local Ext = lazy_require("continuity.core.ext")
local log = lazy_require("continuity.log")

---@class continuity.core.snapshot
local M = {}

local _is_loading = false

--- Returns true if a session is currently being loaded
---@return boolean
function M.is_loading()
  return _is_loading
end

--- Decide whether to include a buffer.
---@param tabpage? continuity.TabNr When saving a tab-scoped session, the tab number.
---@param bufnr continuity.BufNr The buffer to check for inclusion
---@param tabpage_bufs table<continuity.BufNr, true?> When saving a tab-scoped session, the list of buffers that are displayed in the tabpage.
---@param opts continuity.SnapshotOpts
local function include_buf(tabpage, bufnr, tabpage_bufs, opts)
  if not (opts.buf_filter or Config.session.buf_filter)(bufnr, opts) then
    return false
  end
  if not tabpage then
    return true
  end
  return tabpage_bufs[bufnr]
    or (opts.tab_buf_filter or Config.session.tab_buf_filter)(tabpage, bufnr, opts)
end

--- Create a snapshot and return the data.
--- Note: Does not handle modified buffer contents, which requires a path to save to.
---@param target_tabpage? continuity.TabNr
---@param opts? continuity.SnapshotOpts
---@return continuity.Snapshot
---@return continuity.BufContext[] List of included buffers
local function create(target_tabpage, opts)
  opts = opts or {}
  ---@type continuity.Snapshot
  local data = {
    buffers = {},
    tabs = {},
    tab_scoped = target_tabpage ~= nil,
    global = {
      cwd = vim.fn.getcwd(-1, -1),
      height = vim.o.lines - vim.o.cmdheight,
      width = vim.o.columns,
      -- Don't save global options for tab-scoped session
      options = target_tabpage and {}
        or util.opts.get_global(opts.options or Config.session.options),
    },
  }
  local included_bufs = {}
  util.opts.with({ eventignore = "all" }, function()
    ---@type continuity.WinID
    local current_win = vim.api.nvim_get_current_win()
    ---@type table<continuity.BufNr,true?>
    local tabpage_bufs = {}
    if target_tabpage then
      for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(target_tabpage)) do
        local bufnr = vim.api.nvim_win_get_buf(winid)
        tabpage_bufs[bufnr] = true
      end
    end
    local is_unexpected_exit = vim.v.exiting ~= vim.NIL and vim.v.exiting > 0
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if include_buf(target_tabpage, bufnr, tabpage_bufs, opts) then
        local ctx = Buf.ctx(bufnr)
        local in_win = vim.fn.bufwinid(bufnr)
        ---@type continuity.BufData
        local buf = {
          name = ctx.name,
          -- if neovim quit unexpectedly, all buffers will appear as unloaded.
          -- As a hack, we just assume that all of them were loaded, to avoid all of them being
          -- *unloaded* when the session is restored.
          loaded = is_unexpected_exit or vim.api.nvim_buf_is_loaded(bufnr),
          options = util.opts.get_buf(bufnr, opts.options or Config.session.options),
          last_pos = (ctx.restore_last_pos and ctx.last_buffer_pos)
            or vim.api.nvim_buf_get_mark(bufnr, '"'),
          in_win = in_win > 0,
          uuid = ctx.uuid,
        }
        data.buffers[#data.buffers + 1] = buf
        included_bufs[#included_bufs + 1] = ctx
      end
    end
    local current_tabpage = vim.api.nvim_get_current_tabpage()
    local tabpages = target_tabpage and { target_tabpage } or vim.api.nvim_list_tabpages()
    -- When the cmd window (e.g. q:) is active, calling nvim_set_current_tabpage causes an error:
    -- E11: Invalid in command-line window. Try to avoid that error, otherwise abort.
    local skip_set_current = false
    ---@diagnostic disable-next-line: unnecessary-if
    if vim.fn.getcmdwintype() ~= "" then
      if #tabpages > 1 or tabpages[1] ~= current_tabpage then
        -- Setting the current tabpage fails when a cmd window is active.
        -- Since we really only need to do it to save the single tab-scoped option (cmdheight),
        -- warn about it, but resume anyways. This means we cannot assume the current tabpage anywhere,
        -- including in extensions! Also, all tab pages will use cmdheight of the current one.
        log.warn(
          "Command-line window is active. Cannot properly save sessions that contain more tab pages than the active one. At least the cmdheight option will be affected."
        )
      end
      skip_set_current = true
    end
    for _, tabpage in ipairs(tabpages) do
      if not skip_set_current then
        vim.api.nvim_set_current_tabpage(tabpage)
      end
      ---@type continuity.TabData
      local tab = {}
      local tabnr = vim.api.nvim_tabpage_get_number(tabpage)
      if target_tabpage or vim.fn.haslocaldir(-1, tabnr) == 1 then
        tab.cwd = vim.fn.getcwd(-1, tabnr)
      end
      tab.options = util.opts.get_tab(tabpage, opts.options or Config.session.options)
      local winlayout = vim.fn.winlayout(tabnr)
      tab.wins = require("continuity.core.layout").add_win_info_to_layout(
        tabnr,
        winlayout,
        current_win,
        opts
      ) or {}
      data.tabs[#data.tabs + 1] = tab
    end
    if not skip_set_current then
      vim.api.nvim_set_current_tabpage(current_tabpage)
    end

    for ext_name, ext_config in pairs(Config.extensions) do
      local extmod = Ext.get(ext_name)
      if extmod and extmod.on_save and (ext_config.enable_in_tab or not target_tabpage) then
        local ok, ext_data = pcall(extmod.on_save, {
          tabpage = target_tabpage,
        })
        if ok then
          data[ext_name] = ext_data
        else
          vim.notify(
            string.format('[continuity] Extension "%s" save error: %s', ext_name, ext_data),
            vim.log.levels.ERROR
          )
        end
      end
    end
  end)
  return data, included_bufs
end

--- Create a snapshot and return the data.
--- Note: Does not handle modified buffer contents, which requires a path to save to.
---@param target_tabpage? continuity.TabNr Limit the session to this tab. If unspecified, saves global state.
---@param opts? continuity.SnapshotOpts Influence which buffers and options are persisted (overrides global default config).
---@return continuity.Snapshot?
---@return continuity.BufContext[] List of included buffers
function M.create(target_tabpage, opts)
  if _is_loading then
    log.warn("Save triggered while still loading session. Skipping save.")
    return nil, {}
  end
  return create(target_tabpage, opts)
end

--- Save the current global or tabpage state to a path.
--- Also handles changed buffer contents.
---@param name string The name of the session
---@param opts continuity.SnapshotOpts Influence which data is included. Note: Passed through to hooks, is allowed to contain more fields.
---@param target_tabpage? continuity.TabNr Instead of saving everything, only save the current tabpage
---@param session_file string The path to write the session to.
---@param state_dir string The path to write the session-associated data to (modified buffers).
---@return continuity.Snapshot?
---@return continuity.BufContext[] List of included buffers
function M.save_as(name, opts, target_tabpage, session_file, state_dir)
  if _is_loading then
    log.warn("Save triggered while still loading session. Skipping save.")
    return nil, {}
  end
  log.fmt_debug(
    "Saving %s session %s with opts %s",
    target_tabpage and "tab" or "global",
    name,
    opts
  )
  if opts.modified == nil then
    opts.modified = Config.session.modified
  end
  if opts.modified == "auto" then
    opts.modified = false
  end
  -- Most API opts are passed through for the hooks, so opts in this case
  -- should be understood as more like continuity.SaveOpts, not just continuity.SnapshotOpts.
  -- TODO: Type
  Ext.dispatch("pre_save", name, opts --[[@as continuity.HookOpts]], target_tabpage)
  local snapshot, included_bufs = create(target_tabpage, opts)
  if opts.modified then
    snapshot.modified = Buf.save_modified(state_dir, included_bufs)
  else
    -- Forget all saved changes later
    vim.schedule(function()
      Buf.clean_modified(state_dir, {})
    end)
  end
  util.path.write_json_file(session_file, snapshot)
  Ext.dispatch("post_save", name, opts --[[@as continuity.HookOpts]], target_tabpage)
  return snapshot, included_bufs
end

--- Call extensions that implement on_post_bufinit, which is triggered
--- directly after buffers were initialized, before all of them were re-:edited.
--- Extracted from the loading logic to keep DRY.
---@param data table
---@param visible_only bool
local function dispatch_post_bufinit(data, visible_only)
  for ext_name in pairs(Config.extensions) do
    if data[ext_name] then
      local extmod = Ext.get(ext_name)
      if extmod and extmod.on_post_bufinit then
        local ok, err = pcall(extmod.on_post_bufinit, data[ext_name], visible_only)
        if not ok then
          vim.notify(
            string.format("[continuity] Extension %s on_post_bufinit error: %s", ext_name, err),
            vim.log.levels.ERROR
          )
        end
      end
    end
  end
end

---@class continuity.core.snapshot.RestoreOpts
---@field reset? boolean Close everything in this neovim instance. If unset/false, loads the snapshot into one or several clean tabs.
---@field modified? boolean|"auto" If the snapshot contains unsaved buffer modifications, restore them.
---@field state_dir? string Directory session-associated data like unsaved buffer modifications are stored in. Required for `modified` loading.

---@param snapshot continuity.Snapshot
---@param opts continuity.core.snapshot.RestoreOpts
function M.restore(snapshot, opts)
  if opts.modified == nil then
    opts.modified = Config.session.modified
  end
  if opts.modified == "auto" then
    opts.modified = not not snapshot.modified
  end
  _is_loading = true
  layout = require("continuity.core.layout")
  if opts.reset then
    layout.close_everything()
  else
    layout.open_clean_tab()
  end
  if opts.modified and not opts.state_dir then
    log.warn(
      "Requested to restore modified buffers, but state_dir was not passed. Skipping restoration of buffer modifications."
    )
    opts.modified = false
  end

  if not opts.modified and snapshot.modified then
    ---@type continuity.Snapshot
    local shallow_snapshot_copy = {}
    for key, val in pairs(snapshot) do
      if key ~= "modified" then
        ---@diagnostic disable-next-line: assign-type-mismatch
        shallow_snapshot_copy[key] = val
      end
    end
    snapshot = shallow_snapshot_copy
  end

  -- Keep track of buffers that are not displayed for later restoration
  -- to speed up startup
  ---@type continuity.BufData[]
  local buffers_later = {}

  -- Don't trigger autocmds during snapshot restoration
  -- Ignore all messages (including swapfile messages) as well
  util.opts.with({ eventignore = "all", shortmess = "aAF" }, function()
    if not snapshot.tab_scoped then
      -- Set the options immediately
      util.opts.restore_global(snapshot.global.options)
    end

    for ext_name in pairs(Config.extensions) do
      if snapshot[ext_name] then
        local extmod = Ext.get(ext_name)
        if extmod and extmod.on_pre_load then
          local ok, err = pcall(extmod.on_pre_load, snapshot[ext_name])
          if not ok then
            vim.notify(
              string.format("[continuity] Extension %s on_pre_load error: %s", ext_name, err),
              vim.log.levels.ERROR
            )
          end
        end
      end
    end

    local scale = {
      vim.o.columns / snapshot.global.width,
      (vim.o.lines - vim.o.cmdheight) / snapshot.global.height,
    }

    ---@type integer?
    local last_bufnr
    for _, buf in ipairs(snapshot.buffers) do
      if buf.in_win == false then
        buffers_later[#buffers_later + 1] = buf
      else
        last_bufnr = Buf.restore(buf, snapshot, opts.state_dir)
      end
      -- TODO: Restore buffer preview cursor
      -- Cannot restore m" here because unsaved restoration can increase
      -- the number of lines/rows, on which the mark could rely. This is currently
      -- worked around when saving buffers, but can be refactored since
      -- restoration of unsaved changes is now included here.
    end

    dispatch_post_bufinit(snapshot, true)

    -- Ensure the cwd is set correctly for each loaded buffer
    if not snapshot.tab_scoped then
      -- FIXME: This should fire DirChanged[Pre] events
      vim.api.nvim_set_current_dir(snapshot.global.cwd)
    end

    ---@type integer?
    local curwin
    for i, tab in ipairs(snapshot.tabs) do
      if i > 1 then
        vim.cmd.tabnew()
        -- Tabnew creates a new empty buffer. Dispose of it when hidden.
        vim.bo.buflisted = false
        vim.bo.bufhidden = "wipe"
      end
      if tab.cwd then
        vim.cmd.tcd({ args = { tab.cwd } })
      end
      local win = layout.set_winlayout(tab.wins, scale)
      if win then
        curwin = win
      end
      util.opts.restore_tab(tab.options)
    end

    -- curwin can be nil if we saved a session in a window with an unsupported buffer. If this was the only window in the active tabpage,
    -- the user is confronted with an empty, unlisted buffer after loading the session. To avoid that situation,
    -- we will switch to the last restored buffer. If the last restored tabpage has at least a single defined window,
    -- we shouldn't do that though, it can result in unexpected behavior.
    -- TODO: Remember and at least switch to active tabpage if there are multiple.
    if curwin then
      vim.api.nvim_set_current_win(curwin)
    elseif
      snapshot.tabs[#snapshot.tabs]
      and snapshot.tabs[#snapshot.tabs].wins == false
      and last_bufnr
    then
      vim.cmd("buffer " .. last_bufnr)
    end

    for ext_name in pairs(Config.extensions) do
      if snapshot[ext_name] then
        local extmod = Ext.get(ext_name)
        if extmod and extmod.on_post_load then
          local ok, err = pcall(extmod.on_post_load, snapshot[ext_name])
          if not ok then
            vim.notify(
              string.format('[continuity] Extension "%s" on_post_load error: %s', ext_name, err),
              vim.log.levels.ERROR
            )
          end
        end
      end
    end
  end)

  -- Trigger the BufEnter event manually for the current buffer.
  -- It will take care of reloading the buffer to check for swap files,
  -- enable syntax highlighting and load plugins.
  vim.api.nvim_exec_autocmds("BufEnter", { buffer = vim.api.nvim_get_current_buf() })
  -- Schedule the restoration of invisible buffers to speed up startup.
  local restore_triggered = false
  local restore_invisible = function()
    if restore_triggered then
      return
    end
    ---@diagnostic disable-next-line: unused
    restore_triggered = true
    log.debug("Restoring invisible buffers")
    -- Don't trigger autocmds during buffer load (shouldn't be necessary since this autocmd is not nested)
    -- Ignore all messages (including swapfile messages) during buffer restoration
    util.opts.with({ eventignore = "all", shortmess = "aAF" }, function()
      for _, buf in ipairs(buffers_later) do
        Buf.restore(buf, snapshot, opts.state_dir)
      end
      dispatch_post_bufinit(snapshot, false)
    end)
    log.debug("Finished loading session")
    _is_loading = false
  end
  vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
    once = true,
    desc = "Continuity: Restore buffers not shown in windows",
    callback = restore_invisible,
  })
  -- I previously used CursorHold[I] events only, but they are not triggered e.g. when neovim
  -- is not focused. This caused the autosave hook to print warnings since the session
  -- was still loading. Make the final restoration happen in 1s at the latest.
  vim.defer_fn(restore_invisible, 1000)
end

---@class continuity.core.snapshot.RestoreWithHooksOpts: continuity.core.snapshot.RestoreOpts
---@field [any] any Any unhandled opts are also passed through to hooks

--- Restore a saved snapshot. Also handles hooks.
---@param name string The name of the target session. Only used for hooks.
---@param snapshot continuity.Snapshot The snapshot contents
---@param opts continuity.core.snapshot.RestoreWithHooksOpts
---@return continuity.TabNr?
function M.restore_as(name, snapshot, opts)
  if opts.modified == nil then
    opts.modified = Config.session.modified
  end
  if opts.modified == "auto" then
    opts.modified = not not snapshot.modified
  end
  Ext.dispatch("pre_load", name, opts --[[@as continuity.HookOpts]])
  M.restore(snapshot, { modified = opts.modified, state_dir = opts.state_dir, reset = opts.reset })
  Ext.dispatch("post_load", name, opts --[[@as continuity.HookOpts]])
  if snapshot.tab_scoped then
    return vim.api.nvim_get_current_tabpage()
  end
end

return M

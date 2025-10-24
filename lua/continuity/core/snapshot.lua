local Config = require("continuity.config")
local util = require("continuity.util")

local lazy_require = util.lazy_require
local Buf = lazy_require("continuity.core.buf")
local Ext = lazy_require("continuity.core.ext")
local log = lazy_require("continuity.log")

---@class continuity.core.snapshot
local M = {}

---@namespace continuity.core.snapshot
---@using continuity.core

local _is_loading = false

--- Returns true if a session is currently being restored.
---@return boolean is_loading
function M.is_loading()
  return _is_loading
end

--- Decide whether to include a buffer.
---@param tabpage? TabID When saving a tab-scoped session, the tab number.
---@param bufnr BufNr The buffer to check for inclusion
---@param tabpage_bufs table<BufNr, true?> #
---   When saving a tab-scoped session, the list of buffers that are displayed in the tabpage.
---@param opts CreateOpts Snapshot creation options
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

--- Get all global marks, excluding read-only ones (0-9).
--- Note: Marks 0-9 are not actually read-only (vim.api.nvim_buf_set_mark works),
--- but they might need special consideration if included here. (TODO)
---@return table<string, FileMark?> global_marks #
local function get_global_marks()
  return vim
    .iter(vim.fn.getmarklist())
    :filter(function(mark)
      return not mark.mark:find("%d$")
    end)
    :fold({}, function(acc, mark)
      acc[mark.mark:sub(2, 2)] = { mark.file, mark.pos[2], mark.pos[3] }
      return acc
    end)
end

local hist_map = {
  search_history = "/",
  command_history = ":",
  input_history = "@",
  expr_history = "=",
  debug_history = ">",
}

--- Keep an indexed list of buffer names. Used to reduce repetition in snapshots, especially
--- in lists of named marks (jumplist/quickfix/loclist).
---@class BufList
---@field by_name table<string, integer?> Mapping of buffer name to list index
---@field by_index string[] List of buffer names
local BufList = {}

---@return BufList buflist #
function BufList.new()
  return setmetatable({ by_name = {}, by_index = {} }, { __index = BufList })
end

---@overload fun(name: ""): nil
---@overload fun(name: nil): nil
---@overload fun(name: string - ""): integer
---@param name string? Buffer name, usually file path
---@return integer? buf_idx Index of buffer path in buffer list
function BufList:add(name)
  if not name or name == "" then
    return
  end
  if self.by_name[name] then
    return self.by_name[name]
  end
  local idx = #self.by_index + 1
  self.by_name[name] = idx
  self.by_index[idx] = name
  return idx
end

---@param idx integer Index of item to get
---@return string? buffer_name Name of referenced buffer
function BufList:get(idx)
  return self.by_index[idx]
end

--- Get session-specific ShaDa file. Used for history persistence.
---@param snapshot_ctx snapshot.Context Contextual information about the loading session (name, paths)
---@param op "save"|"restore" Operation being beformed, for error log
---@return string? shada_path #
local function get_shada_file(snapshot_ctx, op)
  if not snapshot_ctx.state_dir then
    log.fmt_warn(
      "Cannot handle shada, missing state_dir/context_dir. "
        .. "Ensure you use continuity.core.snapshot.%s_as.",
      op
    )
    return
  end
  return util.path.join(snapshot_ctx.state_dir, "shada")
end

--- Write history entries to ShaDa. Only available in global sessions.
---@param opts snapshot.CreateOpts Snapshot creation options
---@param snapshot_ctx? snapshot.Context Contextual information about the loading session (name, paths)
---@param snapshot Snapshot Snapshot data being restored
---@return Snapshot modified #
local function wshada_hist(opts, snapshot_ctx, snapshot)
  local shada_file = get_shada_file(snapshot_ctx or {}, "save")
  if not shada_file then
    return snapshot
  end
  local shada_opt = vim
    .iter(pairs(hist_map))
    :map(function(conf, char)
      local should_skip = conf == "expr_history" or conf == "debug_history"
      if opts[conf] then
        snapshot["global"][conf] = true
        if conf == "expr_history" or conf == "debug_history" then
          -- These cannot be handled separately when writing.
          return
        end
        return not should_skip and (char .. tostring(opts[conf] ~= true or vim.go.history)) or nil
      end
      return not should_skip and (char .. "0") or nil
    end)
    :join(",")

  ---@diagnostic disable-next-line: unnecessary-if
  if vim.fn.getcmdwintype() ~= "" then
    -- Opening a sacrificial window fails when cmdwin is active.
    -- Still do the dance above to set the corresponding snapshot options.
    local msg =
      "Command-line window is active. Cannot save history without butchering jumplist of active window. Skipping history export."
    log.warn(msg)
    vim.notify_once("Continuity: " .. msg, vim.log.levels.WARN)
    return snapshot
  end

  -- NOTE: Writing shada breaks jumplists in the active window, even if we did not request to store them.
  -- This appears to be fixed in nvim 0.12+: https://github.com/neovim/neovim/pull/33542
  -- It still sets the `'"` mark in all windows (shouldn't matter as much).
  -- We open a temporary window in <0.12 to avoid having to restore the jumplist after writing history shada
  if vim.fn.has("nvim-0.12") == 1 then
    util.opts.with(
      { shada = shada_opt .. ",'0", shadafile = shada_file },
      -- Try to merge with existing shada file
      vim.cmd.wshada,
      { vim.fn.fnameescape(shada_file) }
    )
  else
    -- `lazyredraw` should not be necessary, but better be safe.
    -- There is an issue that erroneously places the cursor in the cmdline,
    -- but I don't think it's triggered if everything works as intended here.
    -- Ref: https://github.com/neovim/neovim/issues/11806
    util.opts.with({ eventignore = "all", lazyredraw = true }, function()
      local curwin = vim.api.nvim_get_current_win()
      -- Use the current buffer specifically to avoid causing a tabline redraw,
      -- which would also exit visual mode.
      local sacrificial_winid = vim.api.nvim_open_win(0, true, {
        relative = "editor",
        row = 0,
        col = 0,
        width = 1,
        height = 1,
        focusable = false,
        hide = true,
        noautocmd = true,
        zindex = 1,
        border = "none",
      })
      util.try_finally(function()
        util.opts.with(
          { shada = shada_opt .. ",'0", shadafile = shada_file },
          -- Try to merge with existing shada file
          vim.cmd.wshada,
          { vim.fn.fnameescape(shada_file) }
        )
      end, function()
        vim.api.nvim_set_current_win(curwin)
        vim.api.nvim_win_close(sacrificial_winid, true)
      end)
    end)
  end
  return snapshot
end

--- Reset histories that are saved in the session and load them from the session ShaDa.
--- Only available in global sessions.
---@param opts snapshot.RestoreOpts Snapshot restoration options
---@param snapshot_ctx? snapshot.Context Contextual information about the loading session (name, paths)
local function rshada_hist(opts, snapshot_ctx)
  local shada_file = get_shada_file(snapshot_ctx or {}, "restore")
  if not shada_file then
    return
  end
  for conf, char in pairs(hist_map) do
    if opts[conf] then
      -- We always want to clear history when loading to start fresh
      vim.fn.histdel(char)
    end
  end
  if not require("continuity.util.path").exists(shada_file) then
    return
  end
  -- Only pull the history entries that should be loaded. Might be relevant
  -- when the config has been switched before regenerating the ShaDa. Also (afaict),
  -- we cannot influence expr/debug histories otherwise. This could be overkill though,
  -- TODO: Reconsider if filtering and thus writing a temp file is necessary here
  util.try_log(function()
    util.shada
      .from_file(shada_file)
      :select({ "history" }, {
        opts.command_history and "cmd" or nil,
        opts.debug_history and "debug" or nil,
        opts.expr_history and "expr" or nil,
        opts.input_history and "input" or nil,
        opts.search_history and "search" or nil,
      })
      :read()
  end, { "Failed to restore history: %s" })
end

--- Create a snapshot and return the data.
--- Note: Does not handle modified buffer contents, which requires a path to save to.
---@param target_tabpage? TabID For tab snapshots, tab number of the tab to snapshot
---@param opts? CreateOpts Snapshot creation options
---@param snapshot_ctx? snapshot.Context Contextual information about the loading session (name, paths)
---@return Snapshot snapshot Snapshot data
---@return BufContext[] included_bufs List of included buffers
local function create(target_tabpage, opts, snapshot_ctx)
  local hist_opts = {
    command_history = util.opts.coalesce_auto("command_history", false, opts, Config.session),
    search_history = util.opts.coalesce_auto("search_history", false, opts, Config.session),
    input_history = util.opts.coalesce_auto("input_history", false, opts, Config.session),
    expr_history = util.opts.coalesce_auto("expr_history", false, opts, Config.session),
    debug_history = util.opts.coalesce_auto("debug_history", false, opts, Config.session),
  }

  -- Indexed list of buffer paths to reduce repetition of (often long) paths, e.g. in jumplists
  local buflist = BufList.new()

  ---@type CreateOpts
  opts = opts or {}
  ---@type Snapshot
  local snapshot = {
    buffers = {},
    tabs = {},
    tab_scoped = target_tabpage ~= nil,
    global = {
      cwd = vim.fn.getcwd(-1, -1),
      height = vim.o.lines - vim.o.cmdheight,
      width = vim.o.columns,
      -- Don't save global options for tab-scoped session
      options = not target_tabpage and util.opts.get_global(opts.options or Config.session.options)
        or {},
      marks = not target_tabpage and opts.global_marks and get_global_marks() or nil,
    },
    buflist = buflist.by_index,
  }

  --- Process history export to shada, if enabled
  if
    not target_tabpage
    and (
      hist_opts.command_history
      or hist_opts.search_history
      or hist_opts.input_history
      or hist_opts.expr_history
      or hist_opts.debug_history
    )
  then
    snapshot = wshada_hist(hist_opts, snapshot_ctx, snapshot)
  end

  local included_bufs = {}
  util.opts.with({ eventignore = "all" }, function()
    ---@type WinID
    local current_win = vim.api.nvim_get_current_win()
    ---@type table<BufNr,true?>
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
        -- NOTE: bufwinid only works for the current tabpage. Buffers in non-current tab
        --       windows are still restored immediately, so this field just avoids a bit
        --       of restoration overhead now.
        local in_win = vim.fn.win_findbuf(bufnr)
        local bt = vim.bo[ctx.bufnr].buftype
        ---@type Snapshot.BufData
        local buf = {
          name = ctx.name,
          -- if neovim quit unexpectedly, all buffers will appear as unloaded.
          -- As a hack, we just assume that all of them were loaded, to avoid all of them being
          -- *unloaded* when the session is restored.
          loaded = is_unexpected_exit or vim.api.nvim_buf_is_loaded(bufnr),
          options = util.opts.get_buf(bufnr, opts.options or Config.session.options),
          last_pos = (ctx.restore_last_pos and ctx.last_buffer_pos)
            or vim.api.nvim_buf_get_mark(bufnr, '"') --[[@as AnonymousMark]],
          in_win = #in_win > 0,
          uuid = ctx.uuid,
          changelist = util.opts.coalesce_auto("changelist", false, opts, Config.session)
            and Buf.parse_changelist(ctx),
          marks = util.opts.coalesce_auto("local_marks", false, opts, Config.session)
            and Buf.get_marks(ctx),
          bt = bt ~= "" and bt or nil,
        }
        snapshot.buffers[#snapshot.buffers + 1] = buf
        included_bufs[#included_bufs + 1] = ctx
        buflist:add(ctx.name)
      end
    end

    local tabpages = target_tabpage and { target_tabpage } or vim.api.nvim_list_tabpages()
    local current_tabpage = not target_tabpage and vim.api.nvim_get_current_tabpage() or nil

    -- We want to avoid mutating the UI state during save at all costs for two reasons:
    --   1) When the cmd window (e.g. q:) is shown, we cannot switch active tab/win/buf:
    --      > E11: Invalid in command-line window.
    --   2) Switching active tab/win/buf can cause a UI redraw, which might reset some state
    --      (most notably exits visual mode) and cause a flicker, especially if floating wins
    --      are visible. This is **hugely** annoying.
    --
    -- Some situations that would cause us to violate that principle:
    --   1) Querying the single tabpage-local `cmdheight` option [tracked via autocmds instead]
    --   2) Opening a scratch window to avoid resetting jumplist for active window when writing
    --      history shada [unnecessary in nvim 0.12+, worked around partially by opening the
    --      current buffer in the window if cmdwintype is empty, otherwise not saving it at all]
    --   3) Querying the jumplist using a window ID (does not work when the window is not in the
    --      current tabpage) [worked around by using tabnr and winnr]
    --
    -- TLDR: Don't rely on active tabpage/window/buffer when saving a snapshot.

    for _, tabpage in ipairs(tabpages) do
      local tabnr = vim.api.nvim_tabpage_get_number(tabpage)
      local winlayout = vim.fn.winlayout(tabnr)
      ---@type Snapshot.TabData
      local tab = {
        cwd = (target_tabpage or vim.fn.haslocaldir(-1, tabnr) == 1) and vim.fn.getcwd(-1, tabnr),
        current = current_tabpage == tabpage,
        options = util.opts.get_tab(tabpage, opts.options or Config.session.options),
        wins = require("continuity.core.layout").add_win_info_to_layout(
          tabnr,
          winlayout,
          current_win,
          opts,
          buflist
        ) or {},
      }
      snapshot.tabs[#snapshot.tabs + 1] = tab
    end

    for ext_name, ext_config in pairs(Config.extensions) do
      local extmod = Ext.get(ext_name)
      if extmod and extmod.on_save and (ext_config.enable_in_tab or not target_tabpage) then
        util.try_log_else(
          extmod.on_save,
          { [1] = "Extension %s save error: %s", [2] = ext_name, notify = true },
          function(ext_data)
            snapshot[ext_name] = ext_data
          end,
          vim.tbl_extend("error", { tabpage = target_tabpage }, snapshot_ctx or {}),
          buflist
        )
      end
    end
  end)
  return snapshot, included_bufs
end

--- Create a snapshot and return the data.
--- Note: Does not handle modified buffer contents, which requires a path to save to.
---@param target_tabpage? TabID #
---   Limit the session to this tab. If unspecified, saves global state.
---@param opts? CreateOpts #
---   Influence which buffers and options are persisted (overrides global default config).
---@param snapshot_ctx snapshot.Context #
---   Snapshot meta information, for creating snapshot-associated files
---   in extensions that cannot (easily) be included in the snapshot table.
---@return Snapshot? snapshot Snapshot data
---@return BufContext[] included_bufs List of included buffers
function M.create(target_tabpage, opts, snapshot_ctx)
  if _is_loading then
    log.warn("Save triggered while still loading session. Skipping save.")
    return nil, {}
  end
  return create(target_tabpage, opts, snapshot_ctx)
end

--- Save the current global or tabpage state to a path.
--- Also handles changed buffer contents.
---@param name string Name of the session
---@param opts CreateOpts & PassthroughOpts Influence which data is included. Note: Passed through to hooks, is allowed to contain more fields.
---@param target_tabpage? TabID Instead of saving everything, only save this tabpage
---@param session_file string Path to write the session to.
---@param state_dir string Path to write session-associated data to (modified buffers).
---@param context_dir string A shared path for all sessions in this context (`dir` for manual sessions, project dir for autosessions)
---@return Snapshot? snapshot Snapshot data
---@return BufContext[] included_bufs List of included buffers
function M.save_as(name, opts, target_tabpage, session_file, state_dir, context_dir)
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
  -- Ensure all hooks receive these two params
  opts.session_file, opts.state_dir, opts.context_dir =
    opts.session_file or session_file, opts.state_dir or state_dir, opts.context_dir or context_dir
  opts.modified = util.opts.coalesce_auto("modified", false, opts, Config.session)
  -- Most API opts and custom ones passed by the user are passed through for the hooks.
  Ext.dispatch("pre_save", name, opts --[[@as ext.HookOpts]], target_tabpage)
  local snapshot, included_bufs = create(target_tabpage, {
    buf_filter = opts.buf_filter,
    options = opts.options,
    tab_buf_filter = opts.tab_buf_filter,
    modified = opts.modified,
    jumps = opts.jumps,
    local_marks = opts.local_marks,
    global_marks = opts.global_marks,
    changelist = opts.changelist,
    command_history = opts.command_history,
    search_history = opts.search_history,
    input_history = opts.input_history,
    expr_history = opts.expr_history,
    debug_history = opts.debug_history,
  }, { name = name, state_dir = state_dir, context_dir = context_dir })
  if opts.modified then
    snapshot.modified = Buf.save_modified(state_dir, included_bufs)
  else
    -- Forget all saved changes later
    vim.schedule(function()
      Buf.clean_modified(state_dir, {})
    end)
  end
  util.path.write_json_file(session_file, snapshot)
  Ext.dispatch("post_save", name, opts --[[@as ext.HookOpts]], target_tabpage)
  return snapshot, included_bufs
end

--- Restore a buffer. Ignores hooks (use `restore_as` instead).
---@param snapshot Snapshot Snapshot data to restore
---@param opts snapshot.RestoreOpts Restoration options
---@param snapshot_ctx snapshot.Context #
---   Snapshot meta information, for creating snapshot-associated files
---   in extensions that cannot (easily) be included in the snapshot table.
function M.restore(snapshot, opts, snapshot_ctx)
  opts.modified =
    util.opts.coalesce_auto("modified", not not snapshot.modified, opts, Config.session)
  for hist_conf, _ in pairs(hist_map) do
    opts[hist_conf] =
      util.opts.coalesce_auto(hist_conf, snapshot.global[hist_conf], opts, Config.session)
  end
  local load_hist = vim
    .iter(hist_map)
    :map(function(v)
      return opts[v]
    end)
    :any(function(v)
      return v
    end)

  _is_loading = true

  local layout = require("continuity.core.layout")
  if opts.reset then
    layout.close_everything()
  else
    layout.open_clean_tab()
  end
  if (opts.modified or load_hist) and not snapshot_ctx.state_dir then
    log.warn(
      "Requested to restore modified buffers or history, but state_dir was not passed. Skipping restoration of buffer modifications/history."
    )
    opts.modified = false
    opts.command_history = false
    opts.search_history = false
    opts.input_history = false
    opts.expr_history = false
    opts.debug_history = false
  end

  if not opts.modified and snapshot.modified then
    log.debug("Not restoring modified buffers persisted in session, opts.modified is false")
    local shallow_snapshot_copy = {}
    for key, val in pairs(snapshot) do
      if key ~= "modified" then
        shallow_snapshot_copy[key] = val
      end
    end
    ---@cast shallow_snapshot_copy Snapshot
    snapshot = shallow_snapshot_copy
  end

  -- Keep track of buffers that are not restored immediately so we know
  -- when snapshot restoration has finished completely.
  local scheduled_bufs = {} ---@type table<BufUUID, true?>

  -- Don't trigger autocmds during snapshot restoration
  -- Ignore all messages (including swapfile messages) as well
  util.opts.with({ eventignore = "all", shortmess = "aAF" }, function()
    if not snapshot.tab_scoped then
      -- Set the options immediately
      util.opts.restore_global(snapshot.global.options)
      -- and restore histories
      if load_hist then
        log.fmt_debug("Clearing + restoring histories. Config: %s", opts)
        rshada_hist(opts, snapshot_ctx)
      end
    end

    Ext.call("on_pre_load", snapshot, snapshot_ctx, snapshot.buflist or {})

    if not snapshot.tab_scoped and opts.global_marks ~= false and snapshot.global.marks then
      log.fmt_debug("Restoring global marks: %s", snapshot.global.marks)
      -- Let's set the global marks via ShaDa to avoid performance impact + interference because
      -- there's only nvim_buf_set_mark, which requires loading the files into bufs and verifies the validity.
      -- We can still clear all unwanted global marks after.
      local gmark_shada = util.shada.new()
      for mark, data in pairs(snapshot.global.marks) do
        gmark_shada:add_gmark(mark, data[1], data[2], data[3])
      end
      util.try_log(gmark_shada.read, { "Failed to restore global marks: %s" }, gmark_shada)
      util.try_log(function()
        -- Clear all global marks that were not defined in the session
        vim
          .iter(vim.fn.getmarklist())
          :map(function(mark)
            return mark.mark:sub(2, 2)
          end)
          :filter(function(name)
            return not snapshot.global.marks[name]
          end)
          :each(vim.api.nvim_del_mark)
      end, { "Failed to reset global marks: %s" })
    end

    local scale = {
      vim.o.columns / snapshot.global.width,
      (vim.o.lines - vim.o.cmdheight) / snapshot.global.height,
    }

    --- Called when a scheduled buffer has been restored.
    ---@param buf Snapshot.BufData
    local function bufrestored(buf)
      scheduled_bufs[buf.uuid] = nil
      log.fmt_trace("Restored deferred buf: %s\nRemaining:%s", buf.uuid, scheduled_bufs)
      if vim.tbl_isempty(scheduled_bufs) then
        util.opts.with(
          { eventignore = "all", shortmess = "aAF" },
          Ext.call,
          "on_post_bufinit",
          snapshot,
          false
        )
        _is_loading = false
        log.trace("Finished loading snapshot")
      end
    end

    ---@type integer?
    local last_bufnr
    local timeout = 500
    local scheduled_cnt = 0
    for _, buf in ipairs(snapshot.buffers) do
      if buf.in_win == false then
        local restore_it = Buf.restore_soon(
          buf,
          snapshot,
          snapshot_ctx.state_dir,
          { timeout = timeout + scheduled_cnt * 30, callback = bufrestored }
        )
        if restore_it then
          scheduled_bufs[buf.uuid] = true
          scheduled_cnt = scheduled_cnt + 1
        end
      else
        last_bufnr = Buf.restore(buf, snapshot, snapshot_ctx.state_dir)
      end
      -- TODO: Restore buffer preview cursor
      -- Cannot restore m" here because unsaved restoration can increase
      -- the number of lines/rows, on which the mark could rely. This is currently
      -- worked around when saving buffers, but can be refactored since
      -- restoration of unsaved changes is now included here.
    end

    Ext.call("on_post_bufinit", snapshot, true)

    -- Ensure the cwd is set correctly for each loaded buffer
    if not snapshot.tab_scoped then
      -- FIXME: This should fire DirChanged[Pre] events
      vim.api.nvim_set_current_dir(snapshot.global.cwd)
    end

    local curwin, curtab, curtab_wincnt ---@type WinID?, TabID?, integer?
    local tabs = {}
    for i, tab in ipairs(snapshot.tabs) do
      if i > 1 then
        vim.cmd.tabnew()
        -- Tabnew creates a new empty buffer. Dispose of it when hidden.
        vim.bo.buflisted = false
        vim.bo.bufhidden = "wipe"
      end
      if tab.cwd then
        vim.cmd.tcd({ args = { vim.fn.fnameescape(tab.cwd) } })
      end
      tabs[i] = vim.api.nvim_get_current_tabpage()
      if tab.current then
        -- Can't rely on tabpagenr later because that assumes 1) reset 2) global scope
        curtab, curtab_wincnt = tabs[i], #(tab.wins or {}) -- or {} to support resession format, which sets `false`
      end
      util.opts.restore_tab(tab.options) -- Restore cmdheight before creating windows
    end

    -- Restore windows in tabs in a second step to avoid window height drift in the first tabpage.
    -- If we restore window height before creating a second tab and `'showtabline'` is 1, with each
    -- save/restore cycle, the lower windows in the first tabpage successively get smaller.
    for i, tab in ipairs(snapshot.tabs) do
      vim.api.nvim_set_current_tabpage(tabs[i])
      curwin = layout.set_winlayout(tab.wins, scale, snapshot.buflist or {}) or curwin
      -- Restore cmdheight again after creating windows because it can drift because of view restoration
      -- (e.g. when more vertical space is available than when snapshot was saved)
      util.opts.restore_tab(tab.options)
      vim.t.continuity_cmdheight_tracker = vim.o.cmdheight -- set this directly because we're ignoring events
    end

    -- curwin can be nil if we saved a session in a window with an unsupported buffer. If this was the only window in the active tabpage,
    -- the user is confronted with an empty, unlisted buffer after loading the session. To avoid that situation,
    -- we will switch to the last restored buffer. If the last restored tabpage has at least a single defined window,
    -- we shouldn't do that though, it can result in unexpected behavior.
    if curwin then
      vim.api.nvim_set_current_win(curwin)
    else
      if curtab then
        vim.api.nvim_set_current_tabpage(curtab)
      end
      if (curtab_wincnt or #(snapshot.tabs[#snapshot.tabs] or {})) == 0 then
        -- This means the active tabpage had a single, unsupported buffer.
        -- Switch to the last loaded buffer in the snapshot, if any.
        -- FIXME: Unsure if this is expected, it's mostly inherited and does not restore jumplist at all.
        --        Consider keeping window layout intact and switching to alternative buffer/going back in
        --        jumplist instead or handling this situation during save.
        if not last_bufnr then
          -- We might not have restored it yet since it wasn't in a window
          for buf in vim.iter(vim.tbl_values(snapshot.buffers)):rev() do
            if buf.loaded then
              last_bufnr = Buf.added(buf.name, buf.uuid).bufnr
              break
            end
          end
        end
        if last_bufnr then
          vim.api.nvim_win_set_buf(0, last_bufnr)
        end
      end
    end

    Ext.call("on_post_load", snapshot, snapshot_ctx)
  end)

  -- Trigger the BufEnter event manually for the current buffer.
  -- It will take care of reloading the buffer to check for swap files,
  -- enable syntax highlighting and load plugins.
  local curbuf = vim.api.nvim_get_current_buf()
  vim.api.nvim_exec_autocmds("BufEnter", { buffer = curbuf })

  if vim.tbl_isempty(scheduled_bufs) then
    _is_loading = false
    log.trace("Finished loading snapshot")
  end

  -- Automatically restore all other windows and visible buffers. This avoids showing partially
  -- restored buffers (missing plugins/LSP annotations...) until a window is focused.
  -- TODO: Consider centralizing the current schedule-as-you-go autocmd logic in the snapshot module.
  --       Autocmds are still necessary because hidden buffers need to be re-:edited the moment they become visible,
  --       but this initial restoration could benefit from more intentional design.

  -- First, create an ordered list of all window IDs at this point, beginning with those in the visible tabpage.
  local restored_wins = vim.api.nvim_tabpage_list_wins(0)
  if snapshot.tab_scoped then
    restored_wins = vim.iter(restored_wins)
  else
    -- FIXME: This assumes the snapshot was loaded with `reset`. It does not hurt to iterate over all
    --        windows since we check if the buffer inside was actually restored by us, but this could
    --        be written in a more efficient way for these cases.
    local othertab_wins = vim
      .iter(vim.api.nvim_list_wins())
      :filter(function(win)
        return not vim.list_contains(restored_wins, win)
      end)
      :totable()
    restored_wins = vim.iter(vim.list_extend(restored_wins, othertab_wins))
  end

  -- Use a timer to rapidly execute autocmds for unfocused buffers/windows
  -- while not blocking the UI any longer than necessary.
  ---@type uv_timer_t
  local edit_timer = assert(vim.uv.new_timer())
  local edited_bufs = { [curbuf] = true } ---@type table<BufNr, true?>
  -- Need to do this very fast (before LSP load) or quite slowly,
  -- otherwise some LSPs might be confused (basedpyright complained about "redundant open text document command").
  -- I noticed that not deferring the first iteration can interfere with some
  -- plugins in the initially focused buffer (loading with focus on a quickfix
  -- buffer + quicker.nvim and setting start to 0 caused an infinite loop)
  edit_timer:start(10, 1, function()
    local win = restored_wins:next()
    if not win then
      return edit_timer:stop()
    end
    vim.schedule(function()
      if not vim.api.nvim_win_is_valid(win) then
        return
      end
      vim.api.nvim_win_call(win, function()
        local bufnr = vim.api.nvim_win_get_buf(win)
        -- Only do this for restored buffers, others don't have this set at all
        if (vim.b[bufnr].continuity_ctx or {}).initialized == nil then
          return
        end
        if not edited_bufs[bufnr] then
          -- Buffer has not been re-:edited yet by this function. Can't rely on the
          -- `initialized` context value because it might not have been set yet.
          edited_bufs[bufnr] = true
          vim.api.nvim_exec_autocmds("BufEnter", { buffer = bufnr })
        else
          -- Buffer is visible in multiple windows, still restore jumplist/cursor.
          vim.api.nvim_exec_autocmds("WinEnter", { buffer = bufnr })
        end
      end)
    end)
  end)
end

--- Restore a saved snapshot. Also handles hooks.
---@param name string Name of the target session. Only used for hooks.
---@param snapshot Snapshot Snapshot data to restore
---@param opts snapshot.RestoreOpts & snapshot.Context & PassthroughOpts
---@return TabID? target_tab #
---   Tab number of the restored tab, if snapshot was tab-scoped.
function M.restore_as(name, snapshot, opts)
  opts.modified =
    util.opts.coalesce_auto("modified", not not snapshot.modified, opts, Config.session)
  for hist_conf, _ in pairs(hist_map) do
    opts[hist_conf] =
      util.opts.coalesce_auto(hist_conf, snapshot.global[hist_conf], opts, Config.session)
  end
  Ext.dispatch("pre_load", name, opts --[[@as ext.HookOpts]])
  M.restore(snapshot, {
    modified = opts.modified,
    reset = opts.reset,
    changelist = opts.changelist,
    jumps = opts.jumps,
    local_marks = opts.local_marks,
    global_marks = opts.global_marks,
    search_history = opts.search_history,
    command_history = opts.command_history,
    input_history = opts.input_history,
    expr_history = opts.expr_history,
    debug_history = opts.debug_history,
  }, { name = name, state_dir = opts.state_dir, context_dir = opts.context_dir })
  Ext.dispatch("post_load", name, opts --[[@as ext.HookOpts]])
  if snapshot.tab_scoped then
    return vim.api.nvim_get_current_tabpage()
  end
end

return M

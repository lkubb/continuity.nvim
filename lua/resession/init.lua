local M = {}

---@diagnostic disable-next-line: deprecated
local uv = vim.uv or vim.loop

local has_setup = false
---@type table?
local pending_config
---@type string?
local current_session
local tab_sessions = {}
local session_configs = {}
local hooks = setmetatable({
  pre_load = {},
  post_load = {},
  pre_save = {},
  post_save = {},
}, {
  __index = function(_, key)
    error(string.format('Unrecognized hook "%s"', key))
  end,
})
local hook_to_event = {
  pre_load = "ResessionLoadPre",
  post_load = "ResessionLoadPost",
  pre_save = "ResessionSavePre",
  post_save = "ResessionSavePost",
}

local function do_setup()
  if pending_config then
    local conf = pending_config
    pending_config = nil
    require("resession.config").setup(conf)

    if not has_setup then
      for hook, _ in pairs(hooks) do
        M.add_hook(hook, function()
          require("resession.util").event(hook_to_event[hook])
        end)
      end
      has_setup = true
    end
  end
end

local function dispatch(name, ...)
  for _, cb in ipairs(hooks[name]) do
    cb(...)
  end
end

---Initialize resession with configuration options
---@param config table
M.setup = function(config)
  pending_config = config or {}
  if has_setup then
    do_setup()
  end
end

---Load an extension some time after calling setup()
---@param name string Name of the extension
---@param opts table Configuration options for extension
M.load_extension = function(name, opts)
  if has_setup then
    local config = require("resession.config")
    local util = require("resession.util")
    config.extensions[name] = opts
    util.get_extension(name)
  elseif pending_config then
    pending_config.extensions = pending_config.extensions or {}
    pending_config.extensions[name] = opts
  else
    error("Cannot call resession.load_extension() before resession.setup()")
  end
end

---Get the name of the current session
---@return string?
M.get_current = function()
  local tabpage = vim.api.nvim_get_current_tabpage()
  return tab_sessions[tabpage] or current_session
end

---Get information about the current session
---@return nil|resession.SessionInfo
M.get_current_session_info = function()
  local session = M.get_current()
  if not session then
    return nil
  end
  local save_dir = session_configs[session].dir
  return {
    name = session,
    dir = save_dir,
    tab_scoped = tab_sessions[vim.api.nvim_get_current_tabpage()] ~= nil,
  }
end

---Detach from the current session
M.detach = function()
  current_session = nil
  local tabpage = vim.api.nvim_get_current_tabpage()
  tab_sessions[tabpage] = nil
end

---List all available saved sessions
---@param opts? resession.ListOpts
---@return string[]
M.list = function(opts)
  opts = opts or {}
  local config = require("resession.config")
  local files = require("resession.files")
  local util = require("resession.util")
  local session_dir = util.get_session_dir(opts.dir)
  if not files.exists(session_dir) then
    return {}
  end
  ---@diagnostic disable-next-line: param-type-mismatch, param-type-not-match, unnecessary-assert
  local fd = assert(uv.fs_opendir(session_dir, nil, 256))
  ---@diagnostic disable-next-line: cast-type-mismatch
  ---@cast fd uv.luv_dir_t
  local entries = uv.fs_readdir(fd)
  local ret = {}
  while entries do
    for _, entry in ipairs(entries) do
      if entry.type == "file" then
        local name = entry.name:match("^(.+)%.json$")
        if name then
          table.insert(ret, name)
        end
      end
    end
    entries = uv.fs_readdir(fd)
  end
  uv.fs_closedir(fd)
  -- Order options
  if config.load_order == "filename" then
    -- Sort by filename
    table.sort(ret)
  elseif config.load_order == "modification_time" then
    -- Sort by modification_time
    local default = { mtime = { sec = 0 } }
    table.sort(ret, function(a, b)
      local file_a = uv.fs_stat(session_dir .. "/" .. a .. ".json") or default
      local file_b = uv.fs_stat(session_dir .. "/" .. b .. ".json") or default
      return file_a.mtime.sec > file_b.mtime.sec
    end)
  elseif config.load_order == "creation_time" then
    -- Sort by creation_time in descending order (most recent first)
    local default = { birthtime = { sec = 0 } }
    table.sort(ret, function(a, b)
      local file_a = uv.fs_stat(session_dir .. "/" .. a .. ".json") or default
      local file_b = uv.fs_stat(session_dir .. "/" .. b .. ".json") or default
      return file_a.birthtime.sec > file_b.birthtime.sec
    end)
  end
  return ret
end

local function remove_tabpage_session(name)
  for k, v in pairs(tab_sessions) do
    if v == name then
      tab_sessions[k] = nil
      break
    end
  end
end

---Delete a saved session
---@param name? string If not provided, prompt for session to delete
---@param opts? resession.DeleteOpts
M.delete = function(name, opts)
  opts = vim.tbl_extend("keep", opts or {}, {
    notify = true,
  })
  local files = require("resession.files")
  local util = require("resession.util")
  if not name then
    local sessions = M.list({ dir = opts.dir })
    if vim.tbl_isempty(sessions) then
      vim.notify("No saved sessions", vim.log.levels.WARN)
      return
    end
    vim.ui.select(
      sessions,
      { kind = "resession_delete", prompt = "Delete session" },
      function(selected)
        if selected then
          M.delete(selected, { dir = opts.dir })
        end
      end
    )
    return
  end
  local filename = util.get_session_file(name, opts.dir)
  if files.delete_file(filename) then
    if opts.notify then
      vim.notify(string.format('Deleted session "%s"', name))
    end
  else
    error(string.format('No session "%s"', filename))
  end
  if current_session == name then
    current_session = nil
  end
  remove_tabpage_session(name)
end

---@param name string
---@param opts resession.SaveOpts
---@param target_tabpage? integer
local function save(name, opts, target_tabpage)
  local config = require("resession.config")
  local files = require("resession.files")
  local layout = require("resession.layout")
  local util = require("resession.util")
  local filename = util.get_session_file(name, opts.dir)
  dispatch("pre_save", name, opts, target_tabpage)
  local eventignore = vim.o.eventignore
  vim.o.eventignore = "all"
  local data = {
    buffers = {},
    tabs = {},
    tab_scoped = target_tabpage ~= nil,
    global = {
      cwd = vim.fn.getcwd(-1, -1),
      height = vim.o.lines - vim.o.cmdheight,
      width = vim.o.columns,
      -- Don't save global options for tab-scoped session
      options = target_tabpage and {} or util.save_global_options(),
    },
  }
  local current_win = vim.api.nvim_get_current_win()
  local tabpage_bufs = {}
  if target_tabpage then
    for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(target_tabpage)) do
      local bufnr = vim.api.nvim_win_get_buf(winid)
      tabpage_bufs[bufnr] = true
    end
  end
  local is_unexpected_exit = vim.v.exiting ~= vim.NIL and vim.v.exiting > 0
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if util.include_buf(target_tabpage, bufnr, tabpage_bufs) then
      if not vim.b[bufnr].resession_uuid then
        vim.b[bufnr].resession_uuid = util.generate_uuid()
      end
      local buf = {
        name = vim.api.nvim_buf_get_name(bufnr),
        -- if neovim quit unexpectedly, all buffers will appear as unloaded.
        -- As a hack, we just assume that all of them were loaded, to avoid all of them being
        -- *unloaded* when the session is restored.
        loaded = is_unexpected_exit or vim.api.nvim_buf_is_loaded(bufnr),
        options = util.save_buf_options(bufnr),
        last_pos = (
          vim.b[bufnr].resession_restore_last_pos
          and vim.b[bufnr].resession_last_buffer_pos
        ) or vim.api.nvim_buf_get_mark(bufnr, '"'),
        uuid = vim.b[bufnr].resession_uuid,
      }
      table.insert(data.buffers, buf)
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
      require("resession.log").warn(
        "Command-line window is active. Cannot properly save sessions that contain more tab pages than the active one. At least the cmdheight option will be affected."
      )
    end
    skip_set_current = true
  end
  for _, tabpage in ipairs(tabpages) do
    if not skip_set_current then
      vim.api.nvim_set_current_tabpage(tabpage)
    end
    local tab = {}
    local tabnr = vim.api.nvim_tabpage_get_number(tabpage)
    if target_tabpage or vim.fn.haslocaldir(-1, tabnr) == 1 then
      tab.cwd = vim.fn.getcwd(-1, tabnr)
    end
    tab.options = util.save_tab_options(tabpage)
    table.insert(data.tabs, tab)
    local winlayout = vim.fn.winlayout(tabnr)
    tab.wins = layout.add_win_info_to_layout(tabnr, winlayout, current_win)
  end
  if not skip_set_current then
    vim.api.nvim_set_current_tabpage(current_tabpage)
  end

  for ext_name, ext_config in pairs(config.extensions) do
    local ext = util.get_extension(ext_name)
    if ext and ext.on_save and (ext_config.enable_in_tab or not target_tabpage) then
      local ok, ext_data = pcall(ext.on_save, {
        tabpage = target_tabpage,
      })
      if ok then
        data[ext_name] = ext_data
      else
        vim.notify(
          string.format('[resession] Extension "%s" save error: %s', ext_name, ext_data),
          vim.log.levels.ERROR
        )
      end
    end
  end

  files.write_json_file(filename, data)
  if opts.notify then
    vim.notify(string.format('Saved session "%s"', name))
  end
  if opts.attach then
    session_configs[name] = {
      dir = opts.dir or config.dir,
    }
  end
  vim.o.eventignore = eventignore
  dispatch("post_save", name, opts, target_tabpage)
end

---Save a session to disk
---@param name? string
---@param opts? resession.SaveOpts
M.save = function(name, opts)
  opts = vim.tbl_extend("keep", opts or {}, {
    notify = true,
    attach = true,
  })
  if not name then
    -- If no name, default to the current session
    name = current_session
  end
  if not name then
    vim.ui.input({ prompt = "Session name" }, function(selected)
      if selected then
        M.save(selected, opts)
      end
    end)
    return
  end
  save(name, opts)
  tab_sessions = {}
  if opts.attach then
    current_session = name
  else
    current_session = nil
  end
end

---Save a tab-scoped session
---@param name? string If not provided, will prompt user for session name
---@param opts? resession.SaveOpts
M.save_tab = function(name, opts)
  opts = vim.tbl_extend("keep", opts or {}, {
    notify = true,
    attach = true,
  })
  local cur_tabpage = vim.api.nvim_get_current_tabpage()
  if not name then
    name = tab_sessions[cur_tabpage]
  end
  if not name then
    vim.ui.input({ prompt = "Session name" }, function(selected)
      if selected then
        M.save_tab(selected, opts)
      end
    end)
    return
  end
  save(name, opts, cur_tabpage)
  current_session = nil
  remove_tabpage_session(name)
  if opts.attach then
    tab_sessions[cur_tabpage] = name
  else
    tab_sessions[cur_tabpage] = nil
  end
end

---Save all current sessions to disk
---@param opts? resession.SaveAllOpts
M.save_all = function(opts)
  opts = vim.tbl_extend("keep", opts or {}, {
    notify = true,
  })
  if current_session then
    save(current_session, vim.tbl_extend("keep", opts, session_configs[current_session]))
  else
    -- First prune tab-scoped sessions for closed tabs
    local invalid_tabpages = vim.tbl_filter(function(tabpage)
      return not vim.api.nvim_tabpage_is_valid(tabpage)
    end, vim.tbl_keys(tab_sessions))
    for _, tabpage in ipairs(invalid_tabpages) do
      tab_sessions[tabpage] = nil
    end
    -- Save all tab-scoped sessions
    for tabpage, name in pairs(tab_sessions) do
      save(name, vim.tbl_extend("keep", opts, session_configs[name]), tabpage)
    end
  end
end

local restore_group = vim.api.nvim_create_augroup("ResessionBufferRestore", { clear = true })

-- Restore cursor positions in buffers/windows if necessary. This is necessary
-- either when a buffer that was hidden when the session was saved is loaded into a window for the first time
-- or when on_buf_load plugins have changed the buffer contents dramatically
-- after the reload triggered by :edit, otherwise the cursor is already restored
-- in util.set_winlayout_data.
---@param bufnr integer The number of the buffer in the currently active window.
---@param win_only boolean? Only restore window-specific cursor positions of the buffer (multiple windows, first one is already recovered)
local function restore_buf_cursor(bufnr, win_only)
  local last_pos
  local current_win
  local log = require("resession.log")
  if win_only and not vim.b[bufnr].resession_last_win_pos then
    -- Sanity check, this should not be triggered
    return
  elseif not win_only and not vim.b[bufnr].resession_last_win_pos then
    -- The buffer is restored for the first time and was hidden when session was saved
    last_pos = vim.b[bufnr].resession_last_buffer_pos
    log.fmt_debug(
      "Buffer %s was not remembered in a window, restoring cursor from buf mark: %s",
      bufnr,
      last_pos
    )
  else
    -- The buffer was at least in one window when saved. If it's this one, restore
    -- its window-specific cursor position (there can be multiple).
    current_win = vim.api.nvim_get_current_win()
    last_pos = vim.b[bufnr].resession_last_win_pos[tostring(current_win)]
    log.fmt_debug(
      "Trying to restore cursor for buf %s in win %s from saved win cursor pos: %s",
      bufnr,
      current_win,
      last_pos
    )
    -- Cannot change individual fields, need to re-assign the whole table
    local temp_pos_table = vim.b[bufnr].resession_last_win_pos
    temp_pos_table[tostring(current_win)] = nil
    vim.b[bufnr].resession_last_win_pos = temp_pos_table
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
        desc = "Resession: restore cursor position of buffer in saved window",
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
    vim.b[bufnr].resession_last_win_pos and vim.tbl_isempty(vim.b[bufnr].resession_last_win_pos)
  then
    -- Clear the window-specific positions of this buffer since all have been applied
    vim.b[bufnr].resession_last_win_pos = nil
  end
  -- The buffer pos is only relevant for buffers that were not in a window when saving,
  -- and from here on only window-specific cursor positions need to be recovered.
  vim.b[bufnr].resession_last_buffer_pos = nil
end

local function finish_restore_buf(bufnr, buf, data)
  local log = require("resession.log")
  -- Save the last position of the cursor for buf_load plugins
  -- that change the buffer text, which can reset cursor position.
  -- set_winlayout_data also sets resession_last_win_pos with window ids
  -- if the buffer was displayed when saving the session.
  -- Extensions can request default restoration by setting resession_restore_last_pos on the buffer
  vim.b[bufnr].resession_last_buffer_pos = buf.last_pos

  log.fmt_debug("Calling on_buf_load extensions")
  local util = require("resession.util")
  local config = require("resession.config")
  for ext_name in pairs(config.extensions) do
    if data[ext_name] then
      local ext = util.get_extension(ext_name)
      if ext and ext.on_buf_load then
        log.fmt_trace(
          "Calling extension %s with bufnr %s and data %s",
          ext_name,
          bufnr,
          data[ext_name]
        )
        local ok, err = pcall(ext.on_buf_load, bufnr, data[ext_name])
        if not ok then
          vim.notify(
            string.format("[resession] Extension %s on_buf_load error: %s", ext_name, err),
            vim.log.levels.ERROR
          )
        end
      end
    end
  end

  if vim.b[bufnr].resession_restore_last_pos then
    log.fmt_debug("Need to restore last cursor pos for buf %s", bufnr)
    vim.b[bufnr].resession_restore_last_pos = nil
    -- Need to schedule this, otherwise it does not work for previously hidden buffers
    -- to restore from mark.
    vim.schedule(function()
      restore_buf_cursor(bufnr)
    end)
  end
end

---@type fun(bufnr: integer, buf: table<string,any>, data: table<string,any>)
local plan_restore

-- Restore a single buffer. This tries to to trigger necessary autocommands that have been
-- suppressed during session loading, then provides plugins the possibility to alter
-- the buffer in some way (e.g. recover unsaved changes) and finally initiates recovery
-- of the last cursor position when a) the buffer was not inside a window when saving or
-- b) on_buf_load plugins reenabled recovery after altering the contents.
---@param bufnr integer The number of the buffer to restore
---@param buf table<string,any> The saved buffer metadata of the buffer to restore
---@param data table<string,any> The extension data saved to the session
local function restore_buf(bufnr, buf, data)
  if not vim.b[bufnr]._resession_need_edit then
    -- prevent recursion in nvim <0.11: https://github.com/neovim/neovim/pull/29544
    return
  end
  vim.b[bufnr]._resession_need_edit = nil
  local log = require("resession.log")
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
      vim.b[bufnr]._resession_swapfile = vim.v.swapname
      -- TODO: better swap handling via swapinfo() and taking continuity into account
    end,
    once = true,
    group = restore_group,
  })
  local finish_restore = vim.api.nvim_create_autocmd("BufEnter", {
    desc = "Resession: complete setup of restored buffer (2)",
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

---@param bufnr integer The number of the buffer to schedule restoration for
---@param buf table<string,any> The saved buffer metadata of the buffer to schedule restoration for
---@param data table<string,any> The extension data saved to the session
function plan_restore(bufnr, buf, data)
  local log = require("resession.log")
  vim.b[bufnr]._resession_need_edit = true
  vim.api.nvim_create_autocmd("BufEnter", {
    desc = "Resession: complete setup of restored buffer (1a)",
    callback = function(args)
      if vim.g._resession_verylazy_done then
        log.fmt_trace("BufEnter triggered for buf %s, VeryLazy done for: %s", bufnr, args)
        restore_buf(bufnr, buf, data)
      else
        log.fmt_trace("BufEnter triggered for buf %s, waiting for VeryLazy for: %s", bufnr, args)
        vim.api.nvim_create_autocmd("User", {
          pattern = "VeryLazy",
          desc = "Resession: complete setup of restored buffer (1b)",
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

local _is_loading = false
---Load a session
---@param name? string
---@param opts? resession.LoadOpts
---    attach? boolean Stay attached to session after loading (default true)
---    reset? boolean|"auto" Close everything before loading the session (default "auto")
---    silence_errors? boolean Don't error when trying to load a missing session
---    dir? string Name of directory to load from (overrides config.dir)
---@note
--- The default value of `reset = "auto"` will reset when loading a normal session, but _not_ when
--- loading a tab-scoped session.
M.load = function(name, opts)
  opts = vim.tbl_extend("keep", opts or {}, {
    reset = "auto",
    attach = true,
  })
  local config = require("resession.config")
  local files = require("resession.files")
  local layout = require("resession.layout")
  local util = require("resession.util")
  local log = require("resession.log")
  if not name then
    local sessions = M.list({ dir = opts.dir })
    if vim.tbl_isempty(sessions) then
      vim.notify("No saved sessions", vim.log.levels.WARN)
      return
    end
    local select_opts = { kind = "resession_load", prompt = "Load session" }
    if config.load_detail then
      local session_data = {}
      for _, session_name in ipairs(sessions) do
        local filename = util.get_session_file(session_name, opts.dir)
        local data = files.load_json_file(filename)
        session_data[session_name] = data
      end
      select_opts.format_item = function(session_name)
        local data = session_data[session_name]
        local formatted = session_name
        if data then
          if data.tab_scoped then
            local tab_cwd = data.tabs[1].cwd
            formatted = formatted .. string.format(" (tab) [%s]", util.shorten_path(tab_cwd))
          else
            formatted = formatted .. string.format(" [%s]", util.shorten_path(data.global.cwd))
          end
        end
        return formatted
      end
    end
    vim.ui.select(sessions, select_opts, function(selected)
      if selected then
        M.load(selected, opts)
      end
    end)
    return
  end
  local filename = util.get_session_file(name, opts.dir)
  local data = files.load_json_file(filename)
  log.fmt_trace("Loading session %s. Data: %s", name, data or "nil")
  if not data then
    if not opts.silence_errors then
      error(string.format('Could not find session "%s"', name))
    end
    return
  end
  dispatch("pre_load", name, opts)
  _is_loading = true
  if opts.reset == "auto" then
    opts.reset = not data.tab_scoped
  end
  if opts.reset then
    util.close_everything()
  else
    util.open_clean_tab()
  end
  -- Don't trigger autocmds during session load
  local eventignore = vim.o.eventignore
  vim.o.eventignore = "all"
  -- Ignore all messages (including swapfile messages) during session load
  local shortmess = vim.o.shortmess
  vim.o.shortmess = "aAF"
  if not data.tab_scoped then
    -- Set the options immediately
    util.restore_global_options(data.global.options)
  end

  for ext_name in pairs(config.extensions) do
    if data[ext_name] then
      local ext = util.get_extension(ext_name)
      if ext and ext.on_pre_load then
        local ok, err = pcall(ext.on_pre_load, data[ext_name])
        if not ok then
          vim.notify(
            string.format("[resession] Extension %s on_pre_load error: %s", ext_name, err),
            vim.log.levels.ERROR
          )
        end
      end
    end
  end

  local scale = {
    vim.o.columns / data.global.width,
    (vim.o.lines - vim.o.cmdheight) / data.global.height,
  }
  -- Special case for folke/lazy.nvim - we want to wait with :edit-ing a buffer
  -- until all plugins are done loading, otherwise some configs might not work as expected.
  if vim.g.lazy_did_setup and not vim.g._resession_verylazy_done then
    vim.g._resession_verylazy_done = false
    vim.api.nvim_create_autocmd("User", {
      pattern = "VeryLazy",
      callback = function()
        vim.g._resession_verylazy_done = true
      end,
      once = true,
    })
  else
    vim.g._resession_verylazy_done = true
  end

  ---@type integer?
  local last_bufnr
  for _, buf in ipairs(data.buffers) do
    local bufnr = util.ensure_buf(buf.name, buf.uuid)
    last_bufnr = bufnr

    if buf.loaded then
      vim.fn.bufload(bufnr)
      vim.b[bufnr].resession_restore_last_pos = true
      plan_restore(bufnr, buf, data)
    end
    vim.b[bufnr].resession_last_buffer_pos = buf.last_pos
    util.restore_buf_options(bufnr, buf.options)
    -- Cannot restore m" here because unsaved restoration can increase
    -- the number of lines/rows, on which the mark could rely. This is currently
    -- worked around when saving buffers, but could be refactored once
    -- restoration of unsaved changes is included here.
  end

  -- TODO: Need to refactor unsaved buffer loading into here for simplicity.
  -- Without this, the buffer preview cursor might be off
  for ext_name in pairs(config.extensions) do
    if data[ext_name] then
      local ext = util.get_extension(ext_name)
      if ext and ext.on_post_bufinit then
        local ok, err = pcall(ext.on_post_bufinit, data[ext_name])
        if not ok then
          vim.notify(
            string.format("[resession] Extension %s on_post_bufinit error: %s", ext_name, err),
            vim.log.levels.ERROR
          )
        end
      end
    end
  end

  -- Ensure the cwd is set correctly for each loaded buffer
  if not data.tab_scoped then
    vim.api.nvim_set_current_dir(data.global.cwd)
  end

  ---@type integer?
  local curwin
  for i, tab in ipairs(data.tabs) do
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
    if tab.options then
      util.restore_tab_options(tab.options)
    end
  end

  -- curwin can be nil if we saved a session in a window with an unsupported buffer, in which case we will switch to
  -- the last restored buffer.
  if curwin then
    vim.api.nvim_set_current_win(curwin)
  elseif last_bufnr then
    vim.cmd("buffer " .. last_bufnr)
  end

  for ext_name in pairs(config.extensions) do
    if data[ext_name] then
      local ext = util.get_extension(ext_name)
      if ext and ext.on_post_load then
        local ok, err = pcall(ext.on_post_load, data[ext_name])
        if not ok then
          vim.notify(
            string.format('[resession] Extension "%s" on_post_load error: %s', ext_name, err),
            vim.log.levels.ERROR
          )
        end
      end
    end
  end

  current_session = nil
  if opts.reset then
    tab_sessions = {}
  end
  remove_tabpage_session(name)
  if opts.attach then
    if data.tab_scoped then
      tab_sessions[vim.api.nvim_get_current_tabpage()] = name
    else
      current_session = name
    end
    session_configs[name] = {
      dir = opts.dir or config.dir,
    }
  end
  vim.o.eventignore = eventignore
  vim.o.shortmess = shortmess
  _is_loading = false
  dispatch("post_load", name, opts)
  -- Trigger the BufEnter event defined above manually for the current buffer.
  -- It will take care of reloading the buffer to check for swap files,
  -- enable syntax highlighting and load plugins.
  vim.api.nvim_exec_autocmds("BufEnter", { buffer = vim.api.nvim_get_current_buf() })
end

---Add a callback that runs at a specific time
---@param name "pre_save"|"post_save"|"pre_load"|"post_load"
---@param callback fun(...: any)
M.add_hook = function(name, callback)
  table.insert(hooks[name], callback)
end

---Remove a hook callback
---@param name "pre_save"|"post_save"|"pre_load"|"post_load"
---@param callback fun(...: any)
M.remove_hook = function(name, callback)
  local cbs = hooks[name]
  for i, cb in ipairs(cbs) do
    if cb == callback then
      table.remove(cbs, i)
      break
    end
  end
end

---The default config.buf_filter (takes all buflisted files with "", "acwrite", or "help" buftype)
---@param bufnr integer
---@return boolean
M.default_buf_filter = function(bufnr)
  local buftype = vim.bo[bufnr].buftype
  if buftype == "help" then
    return true
  end
  if buftype ~= "" and buftype ~= "acwrite" then
    return false
  end
  if vim.api.nvim_buf_get_name(bufnr) == "" then
    return false
  end
  return vim.bo[bufnr].buflisted
end

---Returns true if a session is currently being loaded
---@return boolean
M.is_loading = function()
  return _is_loading
end

-- Make sure all the API functions trigger the lazy load
for k, v in pairs(M) do
  if type(v) == "function" and k ~= "setup" then
    M[k] = function(...)
      do_setup()
      return v(...)
    end
  end
end

return M

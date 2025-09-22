-- Setup autoloading and autosaving of resession sessions per project.

-- TODO: Improve usability, a lot. I'm currently mapping project names
-- to directories by just hashing them, which hinders discoverability.
-- Session names are not escaped in any way, which means branches such
-- as fix/foobar will be rendered into a subdirectory.
-- Consider something like https://github.com/jedrzejboczar/possession.nvim/pull/55
-- or use the registry implementation as a light database.
-- Note that (neo)vim saves undo files with just the pathsep replaced by %,
-- which makes sense since they have to be valid file paths, but we cannot
-- assume project_name is equivalent to a valid path, hence we need some kind
-- of encoding.

-- TODO: Allow creating named sessions other than the default one?

-- TODO: Write tests

-- TODO: Better swapfile handling, see https://github.com/neovim/neovim/issues/5086
-- Refs:
--   https://old.reddit.com/r/neovim/comments/1hkpgar/a_per_project_shadafile/
--   https://github.com/psych3r/vim-remembers/blob/master/plugin/remembers.vim#L86
--   https://github.com/jedrzejboczar/possession.nvim
--   https://github.com/rmagatti/auto-session
--   https://github.com/folke/persistence.nvim
--   https://github.com/olimorris/persisted.nvim
--   https://github.com/Shatur/neovim-session-manager
--   https://github.com/echasnovski/mini.sessions

local Config = require("continuity.config")
local util = require("continuity.util")

local lazy_require = util.lazy_require
local Buf = lazy_require("continuity.core.buf")
local Core = lazy_require("continuity.core")
local Ext = lazy_require("continuity.core.ext")
local log = lazy_require("continuity.log")

---@type continuity.Autosession?
local _current_session
---@type continuity.Autosession?
local _loading_session
---@type table?
local _loading_session_data
-- Monitor the currently active branch and check if we need to reload when it changes
---@type string?
local last_head
-- When an autosession is active, the augroup that monitors for changes (git branch, global cwd)
-- to automatically save and reload when necessary
---@type integer?
local monitor_group

---Renders autosession metadata for a specific directory.
---Returns nil when autosessions are disabled for this directory.
---@param cwd string The working directory the autosession should be rendered for.
---@return continuity.Autosession?
local function render_autosession_context(cwd)
  local workspace, is_git = Config.autosession.workspace(cwd)
  -- normalize workspace dir, ensure trailing /
  workspace = util.path.norm(workspace)
  local git_info
  if is_git then
    git_info = util.git.git_info({ cwd = workspace })
  end
  local project_name = Config.autosession.project_name(workspace, git_info)
  local session_name = Config.autosession.session_name({
    cwd = cwd,
    git_info = git_info,
    project_name = project_name,
    workspace = workspace,
  })
  if
    not Config.autosession.enabled({
      cwd = cwd,
      git_info = git_info,
      project_name = project_name,
      session_name = session_name,
      workspace = workspace,
    })
  then
    return nil
  end
  local project_dir = util.auto.hash(project_name)
  return {
    cwd = cwd,
    name = session_name,
    root = workspace,
    project = {
      name = project_name,
      data_dir = util.path.join(Config.autosession.dir, project_dir),
      repo = git_info,
    },
  }
end

---Save the currently active autosession.
---@param opts? resession.SaveOpts Parameters for resession.save
local function save(opts)
  if not _current_session then
    return
  end
  opts = vim.tbl_extend("force", { attach = true, notify = false }, opts or {})
  opts.dir = _current_session.project.data_dir
  Core.save(_current_session.name, opts)
end

---Remove previously saved buffers and their undo history when they are
---no longer part of Continuity's state (most likely have been written).
---@param state_dir string The path to the modified_buffers directory of the session represented by `data`.
---@param data table Most recently saved session metadata.
local function clean_remembered_buffers(state_dir, data)
  local remembered_buffers = vim.fn.glob(vim.fs.joinpath(state_dir, "*.buffer"), true, true)
  for _, sav in ipairs(remembered_buffers) do
    local uuid = vim.fn.fnamemodify(sav, ":t:r")
    if not data[uuid] then
      pcall(vim.fn.delete, sav)
      pcall(vim.fn.delete, vim.fn.fnamemodify(sav, ":r") .. ".undo")
    end
  end
end

---Iterate over modified buffers, save them and their undo history
---and return data to resession.
---@return table<string, continuity.ManagedBufID>?
local function save_modified_buffers()
  log.fmt_trace("save_modified_buffers called")
  if _loading_session and _loading_session_data then
    log.fmt_warn("save_modified_buffers called before full session restoration")
    return _loading_session_data
  end
  if not _current_session then
    log.fmt_trace("save_modified_buffers skipped: no current session")
    return
  end
  local state_dir = util.path.get_stdpath_filename(
    "data",
    _current_session.project.data_dir,
    _current_session.name,
    "modified_buffers"
  )
  local modified_buffers = Buf.list_modified()
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
  for _, buf in ipairs(modified_buffers) do
    -- Unrestored buffers should not overwrite the save file, but still be remembered
    -- _continuity_unrestored are buffers that were not restored at all due to swapfile and being opened read-only
    -- _continuity_needs_restore are buffers that were restored initially, but have never been entered since loading.
    -- If we saved the latter, we would lose the undo history since it hasn't been loaded for them.
    -- This at least affects unnamed buffers since we solely manage the history for them.
    if not (vim.b[buf.buf]._continuity_unrestored or vim.b[buf.buf]._continuity_needs_restore) then
      local save_file = vim.fs.joinpath(state_dir, buf.uuid .. ".buffer")
      local undo_file = vim.fs.joinpath(state_dir, buf.uuid .. ".undo")
      log.fmt_debug(
        "Saving modified buffer %s (%s) named '%s' to %s",
        buf.buf,
        buf.uuid,
        buf.name,
        save_file
      )

      local ok, msg = pcall(function()
        -- Backup the current buffer contents. Avoid vim.cmd.w because that can have side effects, even with keepalt/noautocmd.
        local lines = vim.api.nvim_buf_get_text(buf.buf, 0, 0, -1, -1, {})
        util.path.write_file(save_file, table.concat(lines, "\n") .. "\n")

        if not skip_wundo then
          vim.api.nvim_buf_call(buf.buf, function()
            vim.cmd.wundo({ undo_file, bang = true, mods = { noautocmd = true, silent = true } })
          end)
        else
          log.fmt_warn(
            "Need to skip backing up undo history for modified buffer %s (%s) named '%s' to %s because cmd window is active",
            buf.buf,
            buf.uuid,
            buf.name,
            undo_file
          )
        end
      end)
      if not ok then
        log.fmt_error(
          "Error saving modified buffer %s (%s) named '%s': %s",
          buf.buf,
          buf.uuid,
          buf.name,
          msg
        )
      end
    else
      log.fmt_debug(
        "Modified buf %s (%s) named '%s' has not been restored yet, skipping save",
        buf.buf,
        buf.uuid,
        buf.name
      )
    end
    res[buf.uuid] = buf
  end
  -- Clean up any remembered buffers that have been removed from the session
  -- or have been saved in the meantime. We can do that after completing the save.
  vim.schedule(function()
    clean_remembered_buffers(state_dir, res)
  end)
  return res
end

---Restore a single modified buffer when it is first focused in a window.
---@param buf integer The buffer ID of the buffer to restore.
---@param data table Continuity save data
local function restore_modified_buffer(buf, data)
  log.fmt_trace("Restoring modified buffer %s with data %s", buf, data)
  local _effective_session = _loading_session or _current_session
  if not _effective_session or not data then
    if not _effective_session then
      log.fmt_debug("No active session to load for buffer %s", buf)
    end
    if not data then
      log.fmt_debug("No data to load for buffer %s", buf)
    end
    return
  end
  if not vim.b[buf].continuity_uuid then
    log.fmt_error(
      "Not restoring '%s' because it does not have an internal uuid set."
        .. " This is likely an internal error.",
      vim.api.nvim_buf_get_name(buf) or "unnamed buffer"
    )
    return
  end
  if not data[vim.b[buf].continuity_uuid] then
    log.fmt_debug("No data to load for unmodified buffer %s", vim.b[buf].continuity_uuid)
    -- Buffer was not modified
    return
  end
  if vim.b[buf]._continuity_swapfile then
    if vim.bo[buf].readonly then
      vim.b[buf]._continuity_unrestored = true
      -- Unnamed buffers should not have a swap file, but account for it anyways
      log.fmt_warn(
        "Not restoring %s because it is read-only, likely because it has an "
          .. "existing swap file and you chose to open it read-only.",
        vim.api.nvim_buf_get_name(buf)
          or ("unnamed buffer with uuid " .. vim.b[buf].continuity_uuid)
      )
      return
    end
    -- TODO: When integrating into resession, add some autodecide logic
    --
    -- if require("continuity.core.files").exists(vim.b[buf]._continuity_swapfile) then
    --   local swapinfo = vim.fn.swapinfo(vim.b[buf]._continuity_swapfile)
    -- end
  end
  local state_dir = util.path.get_stdpath_filename(
    "data",
    _effective_session.project.data_dir,
    _effective_session.name,
    "modified_buffers"
  )
  local save_file = vim.fs.joinpath(state_dir, vim.b[buf].continuity_uuid .. ".buffer")
  if not util.path.exists(save_file) then
    vim.b[buf]._continuity_needs_restore = nil
    log.fmt_warn(
      "Not restoring %s because its save file is missing.",
      vim.api.nvim_buf_get_name(buf) or ("unnamed buffer with uuid " .. vim.b[buf].continuity_uuid)
    )
    return
  end
  log.fmt_debug("Loading buffer changes for buffer %s", vim.b[buf].continuity_uuid, buf)
  local ok, file_lines = pcall(util.path.read_lines, save_file)
  if ok then
    ---@cast file_lines -string
    log.fmt_debug(
      "Loaded buffer changes for buffer %s, loading into %s",
      vim.b[buf].continuity_uuid,
      buf
    )
    vim.api.nvim_buf_set_lines(buf, 0, -1, true, file_lines)
    -- Don't read the undo file if we're inside a recovered buffer, which should ensure the
    -- user can undo the recovery overwrite. This should be handled better.
    if not vim.b[buf]._continuity_swapfile then
      local undo_file = vim.fs.joinpath(state_dir, vim.b.continuity_uuid .. ".undo")
      log.fmt_debug("Loading undo history for buffer %s", vim.b[buf].continuity_uuid)
      local err
      ok, err = pcall(
        vim.api.nvim_cmd,
        { cmd = "rundo", args = { undo_file }, mods = { silent = true } },
        {}
      )
      if not ok then
        log.fmt_error(
          "Failed loading undo history for buffer %s: %s",
          vim.b[buf].continuity_uuid,
          err
        )
      end
    else
      log.warn(
        "Skipped loading undo history for buffer %s because it had a swapfile: %s",
        vim.b[buf].continuity_uuid,
        vim.b[buf]._continuity_swapfile
      )
    end
    vim.b[buf]._continuity_needs_restore = nil
    vim.b[buf].continuity_restore_last_pos = true
  end
  log.fmt_trace("Finished restoring modified buffer %s into %s", vim.b[buf].continuity_uuid, buf)
end

---Restore modified buffers during session load, i.e. before they are re-:edit-ed.
---For presentation purposes only (e.g. ensures unfocused windows show the correct data).
---@param data table Continuity extension save data
---@param visible_only boolean Whether to only restore buffers that are in a window (true) or those that are not (false)
local function restore_modified_buffers(data, visible_only)
  if not _loading_session or not data then
    return
  end
  -- Remember this until we have finished loading in case an autosave
  -- is triggered before full restoration
  _loading_session_data = data
  local state_dir = util.path.get_stdpath_filename(
    "data",
    _loading_session.project.data_dir,
    _loading_session.name,
    "modified_buffers"
  )
  local bufs = Buf.list()
  log.fmt_debug("Restoring modified buffers before reload: %s", data)
  for _, modified in pairs(data) do
    if (modified.in_win == false) ~= visible_only then
      local save_file = vim.fs.joinpath(state_dir, tostring(modified.uuid) .. ".buffer")
      local ok, file_lines = pcall(util.path.read_lines, save_file)
      if not ok then
        log.fmt_warn(
          "Not restoring %s because its save file could not be read: %s",
          modified.uuid,
          file_lines
        )
      else
        ---@cast file_lines -string
        local new_buf
        for _, buf in ipairs(bufs) do
          if buf.uuid == modified.uuid then
            new_buf = buf.buf
            break
          end
        end
        -- NOTE: This should not be needed during regular operation. Can be avoided by integrating this into resession
        if not new_buf and modified.name ~= "" then
          -- in case something has gone wrong, at least restore named buffers
          for _, buf in ipairs(bufs) do
            if buf.name == modified.name then
              new_buf = buf.buf
              break
            end
          end
        end
        log.fmt_debug("Restoring modified buf %s into bufnr %s", modified.uuid, new_buf)
        ---@diagnostic disable-next-line: unnecessary-if
        if new_buf then
          vim.api.nvim_buf_set_lines(new_buf, 0, -1, true, file_lines)
          -- Ensure autocmd :edit works. It will trigger the final restoration.
          -- Don't do it for unnamed buffers since :edit cannot be called for them.
          if modified.name ~= "" then
            vim.bo[new_buf].modified = false
          end
          -- Ensure the buffer is remembered as modified if it is never loaded until the next save
          vim.b[new_buf]._continuity_needs_restore = true
        end
      end
    end
  end
  if not visible_only then
    -- This means we have restored everything now, not just visible buffers.
    _current_session, _loading_session, _loading_session_data = _loading_session, nil, nil
  end
end

---Save the currently active autosession and stop autosaving it after.
---Does not close anything after detaching.
---@param opts? resession.SaveOpts Parameters for resession.save
local function detach(opts)
  if not _current_session then
    return
  end
  opts = vim.tbl_extend("force", opts or {}, { attach = false })
  save(opts)
  _current_session = nil
end

---@type fun(autosession: continuity.Autosession?)
local monitor

---Load an autosession.
---@param autosession (continuity.Autosession|string)? The autosession table as rendered by render_autosession_context
---@param opts resession.LoadOpts? Parameters for resession.load. silence_errors is forced to true.
local function load(autosession, opts)
  if type(autosession) == "string" then
    autosession = render_autosession_context(autosession)
  end
  monitor(autosession)
  if not autosession then
    return
  end
  -- No need to detach, it's handled by the pre-load hook.
  opts = vim.tbl_extend(
    "force",
    { attach = true, reset = true },
    opts or {},
    { silence_errors = false }
  )
  opts.dir = autosession.project.data_dir

  _loading_session = autosession
  -- TODO: Use xpcall and error handler to show better stacktrace
  local ok, err = pcall(Core.load, autosession.name, opts)
  -- Only set current session after finishing buffer restoration (restore_modified_buffers)
  -- to allow pre-load hook to function properly.

  if not ok then
    ---@cast err string
    if not err:find("Could not find session", nil, true) then
      vim.notify("Error loading session: " .. err, vim.log.levels.ERROR)
      return
    end
    -- TODO: Check if error message actually contains 'Could not find session',
    -- meaning we didn't fail for some other reason.
    --
    -- The session did not exist, need to save.
    -- First, change cwd to workspace root since resession saves/restores cwd.
    vim.api.nvim_set_current_dir(autosession.root)
    -- This also means there is nothing to restore anymore.
    -- If we had a session before, the above call only loads visible buffers
    -- and waits for the first CursorHold event to load the rest.
    _loading_session = nil
    _current_session = autosession
    save()
  end
end

---If an autosession is active, save it and detach. Then try to start a new one.
local function reload()
  log.fmt_trace("Reload called. Checking if we need to reload")
  local effective_cwd = util.auto.cwd()
  local autosession = render_autosession_context(effective_cwd)
  if not autosession then
    if _current_session then
      log.fmt_trace("Reload check result: New context disables active autosession")
      detach()
      require("continuity.core.layout").close_everything()
    else
      log.fmt_trace(
        "Reload check result: No active autosession, new context is disabled as well. Nothing to do."
      )
    end
    return
  end
  if
    _current_session
    and _current_session.project.name == autosession.project.name
    and _current_session.name == autosession.name
  then
    log.fmt_trace(
      "Reload check result: Not reloading because new context has same project and session name as active session"
    )
    return
  end
  log.fmt_trace(
    "Reloading. Current session:\n%s\nNew session:\n%s",
    _current_session or "nil",
    autosession
  )
  -- Don't call save here, it's done in a pre_load hook which calls detach().
  load(autosession)
end

---Remove all monitoring hooks.
local function stop_monitoring()
  if monitor_group then
    vim.api.nvim_clear_autocmds({ group = monitor_group })
    monitor_group = nil
  end
  last_head = nil
  -- TODO: Should we remove buffer-local variables like _continuity_needs_restore?
end

---Load the continuity extension for resession and create hooks that:
---1. When resession loads another session, try to detach/save an active autosession.
---2. When neovim exits, save an active autosession.
---3. When the session is associated with a git repo and gitsigns is available, save/detach/reload active autosession on branch changes.
---4. When the global CWD changes, save/detach/reload active autosession.
---@param autosession continuity.Autosession? The active autosession that should be monitored
function monitor(autosession)
  monitor_group = vim.api.nvim_create_augroup("ContinuityHooks", { clear = true })

  -- Add extension for save/restore of unsaved buffers. Note: This is idempotent
  Ext.load_extension("continuity", {})

  ---@type boolean?
  local gitsigns_in_sync = false
  local autosession_head = autosession
    and autosession.project.repo
    and autosession.project.repo.branch
  last_head = nil

  if not autosession then
    -- If we're not inside an autosession currently, just set it later so it's
    -- in sync with gitsigns
    gitsigns_in_sync = nil
  ---@diagnostic disable-next-line: unnecessary-if
  elseif vim.g.gitsigns_head then
    if vim.g.gitsigns_head == "" then
      log.debug("vim.g.gitsigns_head is empty string, this is likely an empty repo")
    elseif not autosession_head then
      log.debug("vim.g.gitsigns_head is set, while the loading autosession does not have a branch")
    ---@diagnostic disable-next-line: need-check-nil
    elseif vim.g.gitsigns_head ~= autosession.project.repo.branch then
      log.debug("vim.g.gitsigns_head does not match autosession branch")
    else
      last_head = vim.g.gitsigns_head
      gitsigns_in_sync = true
    end
  elseif autosession_head then
    log.debug(
      "vim.g.gitsigns_head is not set, while the loading autosession has a branch. Either gitsigns is not enabled or needs to catch up still"
    )
  else
    gitsigns_in_sync = true
  end

  vim.defer_fn(function()
    -- Integrate with GitSigns to watch current branch, but not immediately after start
    -- to avoid race conditions
    vim.api.nvim_create_autocmd("User", {
      pattern = "GitSignsUpdate",
      callback = function()
        if not gitsigns_in_sync then
          if gitsigns_in_sync == nil then
            -- We don't have an active session, just follow gitsigns' lead
            autosession_head = vim.g.gitsigns_head
          elseif autosession_head ~= vim.g.gitsigns_head then
            -- gitsigns does not assign this in 'detached' state (e.g. bare repo with worktree)
            -- and assigns an empty string when it's an empty repo.
            -- In either case, we don't want to react here. This means worktrees are not watched for branch changes.
            return
          end
          ---@diagnostic disable-next-line: unused
          gitsigns_in_sync = true
          last_head = autosession_head
        end
        if last_head ~= vim.g.gitsigns_head then
          log.fmt_trace(
            "Reloading project, switched from branch %s to branch %s",
            last_head or "nil",
            vim.g.gitsigns_head or "nil"
          )
          reload()
        end
        ---@diagnostic disable-next-line: unused
        last_head = vim.g.gitsigns_head
      end,
      group = monitor_group,
    })
  end, 500)

  vim.api.nvim_create_autocmd("DirChangedPre", {
    pattern = "global",
    callback = function()
      log.fmt_trace(
        "DirChangedPre: Global directory is going to change, checking if we need to detach before"
      )
      if not _current_session or _loading_session then
        -- We don't need to detach if we don't have an active session or
        -- if we're in the process of loading one
        return
      end
      ---@diagnostic disable-next-line: undefined-field
      local lookahead = render_autosession_context(vim.v.event.directory)
      if
        not lookahead
        or _current_session.project.name ~= lookahead.project.name
        or _current_session.name ~= lookahead.name
      then
        log.fmt_trace(
          "DirChangedPre: Need to detach because session is going to change. Current session:\n%s\nNew session:\n%s",
          _current_session,
          lookahead or "nil"
        )
        -- We're going to switch/disable the active autosession.
        -- Ensure we detach before the global cwd is changed, otherwise
        -- Resession saves the new one in the current session instead.
        detach()
      end
    end,
    group = monitor_group,
  })
  vim.api.nvim_create_autocmd("DirChanged", {
    pattern = "global",
    callback = function()
      if not _loading_session then
        log.fmt_trace("DirChanged: trying reload")
        reload()
      end
    end,
    group = monitor_group,
  })
end

---Start Continuity:
---1. If the current working directory has an associated project and session, closes everything and loads that session.
---2. In any case, start monitoring for directory or branch changes.
---@param cwd string? The working directory to switch to before starting autosession. Defaults to nvim's process' cwd.
---@param opts resession.LoadOpts? Parameters for resession.load. silence_errors is forced to true.
local function start(cwd, opts)
  load(cwd or util.auto.cwd(), opts)
end

---Stop Continuity:
---1. If we're inside an active autosession, save it and detaches. Does not close everything by default.
---2. In any case, stop monitoring for directory or branch changes.
local function stop()
  stop_monitoring()
  if _current_session then
    detach()
  end
end

---@class continuity.ResetOpts: resession.DeleteOpts
---@field reload? boolean Restart a new autosession after reset. Defaults to true.

---Reset the currently active autosession. Closes everything.
---@param opts? continuity.ResetOpts Options to influence execution (TODO docs)
local function reset(opts)
  if not _current_session then
    return
  end
  local _last_session
  _last_session, _current_session = _current_session, nil
  opts = vim.tbl_extend("force", { notify = false }, opts or {})
  opts.dir = _last_session.project.data_dir
  Core.detach()
  Core.delete(_last_session.name, opts)
  require("continuity.core.layout").close_everything()
  if opts.reload ~= false then
    reload()
  end
end

---Remove all autosessions associated with a project.
---If the target is the active project, resets current session as well and closes everything.
---@param opts {name?: string}? Specify the project to reset. If unspecified, resets active project, if available.
local function reset_project(opts)
  opts = opts or {}
  local name = opts.name
  if not name then
    if not _current_session then
      return
    end
    name = _current_session.project.name
  end

  local continuity_dir = util.path.get_session_dir(Config.autosession.dir)
  local project_dir = util.path.join(continuity_dir, util.auto.hash(name))
  if not util.path.exists(project_dir) then
    return
  end

  local resetting_active = false
  -- If we're resetting the active project, ensure we detach from the active session before deleting the data
  if _current_session and project_dir:find(_current_session.project.data_dir) then
    reset({ reload = false })
    resetting_active = true
  end

  local expected_parent = util.path.get_stdpath_filename("data", "continuity")
  assert(project_dir:sub(1, #expected_parent) == expected_parent) -- sanity check before recursively deleting
  util.path.rmdir(project_dir, { recursive = true })

  if resetting_active then
    reload()
  end
end

---List autosessions associated with a project.
---@param opts {cwd?: string}? Specify the project to list. If unspecified, lists active project, if available.
---@return string[]
local function list(opts)
  opts = opts or {}
  local ctx = render_autosession_context(opts.cwd or assert(util.auto.cwd_init()))
  if ctx then
    return Core.list({ dir = ctx.project.data_dir })
  end
  return {}
end

---List all known projects.
---@return string[]
local function list_projects()
  --TODO: This is quite inefficient and could benefit from an inventory somewhere.
  local projects = {}

  local continuity_dir = util.path.get_session_dir(Config.autosession.dir)
  for name, typ in vim.fs.dir(continuity_dir) do
    if typ == "directory" then
      local save_file = vim.fs.find(function(fname)
        return fname:match(".*%.json$")
      end, { limit = 1, path = util.path.join(continuity_dir, name) })
      if save_file[1] then
        local save_contents = util.path.load_json_file(save_file[1])
        local cwd = save_contents.global.cwd
        if util.path.exists(cwd) then
          local ctx = render_autosession_context(cwd)
          if ctx then
            projects[#projects + 1] = ctx.project.name
          end
        end
      end
    end
  end
  return projects
end

---Dev helper currently (beware: unstable/inefficient).
---When changing the mapping from workspace to project name, all previously
---saved states would be lost. This tries to migrate state data to the new mapping,
---cleans projects whose cwd does not exist anymore or which are disabled
---Caution! This does not account for projects with multiple associated directories/sessions!
---Checks the first session's cwd/enabled state only!
local function migrate_projects()
  local ret = {
    broken = {},
    missing = {},
    skipped = {},
    migrated = {},
    deactivated = {},
    duplicate = {},
    errors = {},
  }

  local function rm(dir, scope, root)
    local ok, msg = pcall(util.path.rmdir, dir, { recursive = true })
    if ok then
      table.insert(ret[scope], { root = root, old_dir = dir })
    else
      table.insert(ret.errors, { type = scope, root = root, old_dir = dir, msg = msg })
    end
  end

  local function mv(old, new, root, new_name)
    if util.path.exists(new) then
      table.insert(ret.errors, {
        type = "migration",
        root = root,
        old_dir = old,
        new_dir = new,
        msg = "Target project exists, cannot merge",
      })
      -- rm(old, "duplicate", root)
    else
      local ok, msg = pcall(os.rename, old, new)
      if ok then
        table.insert(ret.migrated, {
          root = root,
          new_name = new_name,
        })
      else
        table.insert(ret.errors, {
          type = "migration",
          root = root,
          new_name = new_name,
          old_dir = old,
          new_dir = new,
          msg = msg,
        })
      end
    end
  end

  local continuity_dir = util.path.get_session_dir(Config.autosession.dir)
  for name, typ in vim.fs.dir(continuity_dir) do
    if typ == "directory" then
      local project_dir = util.path.join(continuity_dir, name)
      local save_file = vim.fs.find(function(fname)
        return fname:match(".*%.json$")
      end, { limit = 1, path = project_dir })
      if save_file[1] then
        local save_contents = util.path.load_json_file(save_file[1])
        local cwd = save_contents.global.cwd
        if not cwd or cwd == "" or vim.fn.isabsolutepath(cwd) == 0 then
          rm(project_dir, "broken", cwd)
        elseif util.path.exists(cwd) then
          local ctx = render_autosession_context(cwd)
          if ctx then
            if not ctx.project.data_dir:find(name, nil, true) then
              local new_dir = util.path.join(continuity_dir, util.auto.hash(ctx.project.name))
              mv(project_dir, new_dir, cwd, ctx.project.name)
            else
              table.insert(ret.skipped, { root = cwd, name = ctx.project.name })
            end
          else
            -- FIXME: This would delete related sessions, not sure if sensible for a broader application
            rm(project_dir, "deactivated", cwd)
          end
        else
          rm(project_dir, "missing", cwd)
        end
      end
    end
  end
  return ret
end

---Return info about the currently active autosession.
---@return {current_session: continuity.Autosession|false, current_session_data?: table}
local function info()
  return {
    current_session = _current_session and vim.deepcopy(_current_session) or false,
    current_session_data = _current_session and util.path.load_json_file(
      util.path.get_session_file(_current_session.name, _current_session.project.data_dir)
    ),
  }
end

---@param opts continuity.UserConfig?
local function setup(opts)
  Config.setup(opts)
end

---@class continuity
local M = {
  save = save,
  reset = reset,
  reset_project = reset_project,
  list = list,
  list_projects = list_projects,
  migrate_projects = migrate_projects,
  reload = reload,
  load = load,
  detach = detach,
  setup = setup,
  start = start,
  stop = stop,
  save_modified_buffers = save_modified_buffers,
  restore_modified_buffers = restore_modified_buffers,
  restore_modified_buffer = restore_modified_buffer,
  info = info,
}

return M

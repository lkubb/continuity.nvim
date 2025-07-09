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

-- TODO: Hooks for changing cwd and current git branch (watch <gitdir>/HEAD with uv.fs_event)

-- TODO: Reset autosession (~ delete)
--
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

local config = require("continuity.config")
local util = require("continuity.util")

---@class Continuity.Autosession
---@field cwd string The working directory neovim was started from before entering an autosession
---@field workspace string The root directory of the current workspace
---@field project_name string The name of the project the current workspace is part of, usually the same (unless git worktrees are used)
---@field project_dir string The name of the project directory used for resession
---@field session string The name of the session for resession
---@field dir string The project's full session directory relative to the nvim data dir

---@type Continuity.Autosession?
local _current_session
---@type Continuity.Autosession?
local _loading_session

-- Receives the effective cwd of the current invocation and returns project metadata.
---@param effective_cwd string The effective working directory of the nvim invocation
---@return Continuity.Autosession?
local function render_autosession_context(effective_cwd)
  local workspace, is_git = config.opts.workspace(effective_cwd)
  workspace = vim.fn.fnamemodify(workspace, ":p") -- normalize workspace dir, adds trailing /
  local project_name = config.opts.project_name(workspace, is_git)
  if not config.opts.enabled(effective_cwd, workspace, project_name) then
    return nil
  end
  local project_dir = config.opts.project_encode(project_name)
  local session_name = config.opts.session_name(effective_cwd, workspace, project_name)
  return {
    cwd = effective_cwd,
    workspace = workspace,
    project_name = project_name,
    project_dir = project_dir,
    session = session_name,
    dir = vim.fs.joinpath(config.opts.dir, project_dir),
  }
end

-- Save the currently active autosession.
---@param opts? resession.SaveOpts Parameters for resession.save
local function save(opts)
  if not _current_session then
    return
  end
  opts = vim.tbl_extend("force", { attach = true, notify = false }, opts or {})
  opts.dir = _current_session.dir
  require("resession").save(_current_session.session, opts)
end

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

local function save_modified_buffers()
  if not _current_session then
    return
  end
  local state_dir = vim.fs.joinpath(
    vim.fn.stdpath("data"),
    _current_session.dir,
    _current_session.session,
    "modified_buffers"
  )
  local modified_buffers = util.list_modified_buffers()
  local active_buf = vim.api.nvim_get_current_buf()
  config.log.fmt_debug(
    "Saving modified buffers in state dir (%s)\nModified buffers: %s",
    state_dir,
    modified_buffers
  )
  local ok, err = pcall(vim.fn.mkdir, state_dir, "p")
  if not ok then
    config.log.fmt_error("Error making state dir: %s", err)
    return
  end
  local res = {}
  for _, buf in ipairs(modified_buffers) do
    -- Unrestored buffers should not overwrite the save file, but still be remembered
    if not vim.b[buf.buf]._continuity_unrestored then
      local save_file = vim.fs.joinpath(state_dir, buf.uuid .. ".buffer")
      local undo_file = vim.fs.joinpath(state_dir, buf.uuid .. ".undo")
      config.log.fmt_debug(
        "Saving modified buffer %s (%s) named '%s' to %s",
        buf.buf,
        buf.uuid,
        buf.name,
        save_file
      )
      -- TODO: use nvim_buf_call
      vim.api.nvim_set_current_buf(buf.buf)
      vim.cmd.w({ save_file, bang = true })
      vim.cmd.wundo({ undo_file, bang = true })
      ok, err = pcall(vim.cmd.setlocal, "nomodified")
      -- FIXME: Necessary/issue?
      if not ok then
        config.log.fmt_debug("Error setting nomodified: ", err)
      end
    else
      config.log.fmt_debug(
        "Modified buf %s (%s) named '%s' has not been restored yet, skipping save",
        buf.buf,
        buf.uuid,
        buf.name
      )
    end
    res[buf.uuid] = buf
  end
  vim.api.nvim_set_current_buf(active_buf)
  -- Clean up any remembered buffers that have been removed from the session
  -- or have been saved in the meantime. We can do that after completing the save.
  vim.schedule(function()
    clean_remembered_buffers(state_dir, res)
  end)
  return res
end

-- Restores a single modified buffer on load.
local function restore_modified_buffer(buf, data)
  config.log.fmt_trace("Restoring modified buffer %s with data %s", buf, data)
  local _effective_session = _loading_session or _current_session
  if not _effective_session or not data then
    if not _effective_session then
      config.log.fmt_debug("No active session to load for buffer %s", buf)
    end
    if not data then
      config.log.fmt_debug("No data to load for buffer %s", buf)
    end
    return
  end
  if not vim.b[buf].resession_uuid then
    config.log.fmt_error(
      "Not restoring '%s' because it does not have an internal uuid set."
        .. " This is likely an internal error.",
      vim.api.nvim_buf_get_name(buf) or "unnamed buffer"
    )
    return
  end
  if not data[vim.b[buf].resession_uuid] then
    config.log.fmt_debug("No data to load for unmodified buffer %s", vim.b[buf].resession_uuid)
    -- Buffer was not modified
    return
  end
  if vim.b[buf]._resession_swapfile then
    if vim.bo[buf].readonly then
      vim.b[buf]._continuity_unrestored = true
      -- Unnamed buffers should not have a swap file, but account for it anyways
      config.log.fmt_warn(
        "Not restoring %s because it is read-only, likely because it has an "
          .. "existing swap file and you chose to open it read-only.",
        vim.api.nvim_buf_get_name(buf) or ("unnamed buffer with uuid " .. vim.b[buf].resession_uuid)
      )
      return
    end
    -- TODO: When integrating into resession, add some autodecide logic
    --
    -- if require("resession.files").exists(vim.b[buf]._resession_swapfile) then
    --   local swapinfo = vim.fn.swapinfo(vim.b[buf]._resession_swapfile)
    -- end
  end
  local state_dir = vim.fs.joinpath(
    vim.fn.stdpath("data"),
    _effective_session.dir,
    _effective_session.session,
    "modified_buffers"
  )
  local save_file = vim.fs.joinpath(state_dir, vim.b[buf].resession_uuid .. ".buffer")
  if not require("resession.files").exists(save_file) then
    vim.b[buf]._continuity_needs_restore = nil
    config.log.fmt_warn(
      "Not restoring %s because its save file is missing.",
      vim.api.nvim_buf_get_name(buf) or ("unnamed buffer with uuid " .. vim.b[buf].resession_uuid)
    )
    return
  end
  config.log.fmt_debug("Loading buffer changes for buffer %s", vim.b[buf].resession_uuid, buf)
  local ok, file_lines = pcall(util.read_lines, save_file)
  if ok then
    config.log.fmt_debug(
      "Loaded buffer changes for buffer %s, loading into %s",
      vim.b[buf].resession_uuid,
      buf
    )
    vim.api.nvim_buf_set_lines(buf, 0, -1, true, file_lines)
    -- Don't read the undo file if we're inside a recovered buffer, which should ensure the
    -- user can undo the recovery overwrite. This should be handled better.
    if not vim.b[buf]._resession_swapfile then
      local undo_file = vim.fs.joinpath(state_dir, vim.b.resession_uuid .. ".undo")
      config.log.fmt_debug("Loading undo history for buffer %s", vim.b[buf].resession_uuid)
      local err
      ok, err = pcall(
        vim.api.nvim_cmd,
        { cmd = "rundo", args = { undo_file }, mods = { silent = true } },
        {}
      )
      if not ok then
        config.log.fmt_error(
          "Failed loading undo history for buffer %s: %s",
          vim.b[buf].resession_uuid,
          err
        )
      end
    end
    vim.b[buf]._continuity_needs_restore = nil
    vim.b[buf].resession_restore_last_pos = true
  end
  config.log.fmt_trace(
    "Finished restoring modified buffer %s into %s",
    vim.b[buf].resession_uuid,
    buf
  )
end

-- Restores modified buffers before they are re-:edit-ed for
-- presentation purposes only.
local function restore_modified_buffers(data)
  if not _loading_session or not data then
    return
  end
  local state_dir = vim.fs.joinpath(
    vim.fn.stdpath("data"),
    _loading_session.dir,
    _loading_session.session,
    "modified_buffers"
  )
  local bufs = util.list_buffers()
  config.log.fmt_debug("Restoring modified buffers before reload: %s", data)
  for _, modified in pairs(data) do
    local save_file = vim.fs.joinpath(state_dir, tostring(modified.uuid) .. ".buffer")
    local ok, file_lines = pcall(util.read_lines, save_file)
    if not ok then
      config.log.fmt_warn(
        "Not restoring %s because its save file could not be read: %s",
        modified.uuid,
        file_lines
      )
    else
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
      config.log.fmt_debug("Restoring modified buf %s into bufnr %s", modified.uuid, new_buf)
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

-- Save the currently active autosession and stop autosaving it after.
---@param opts? resession.SaveOpts Parameters for resession.save
local function detach(opts)
  if not _current_session then
    return
  end
  opts = vim.tbl_extend("force", opts or {}, { attach = false })
  save(opts)
  _current_session = nil
end

-- Load an autosession.
---@param autosession Continuity.Autosession? The autosession table as rendered by render_autosession_context
---@param opts resession.LoadOpts? Parameters for resession.load. silence_errors is forced to true.
local function load(autosession, opts)
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
  opts.dir = autosession.dir
  local resession = require("resession")

  _loading_session = autosession
  local ok, err = pcall(resession.load, autosession.session, opts)
  -- Only set current session after loading it to allow pre-load hook
  -- to function properly.
  _loading_session = nil
  _current_session = autosession

  if not ok then
    vim.notify("error loading session: " .. err)
    -- TODO: Check if error message actually contains 'Could not find session',
    -- meaning we didn't fail for some other reason.
    --
    -- The session did not exist, need to save.
    -- First, change cwd to workspace root since resession saves/restores cwd.
    vim.api.nvim_set_current_dir(autosession.workspace)
    save()
  end
end

-- When Continuity determines it should run, create hooks to ensure the session is saved automatically.
local function create_hooks()
  local autosave_group = vim.api.nvim_create_augroup("ContinuityHooks", { clear = true })
  local resession = require("resession")

  -- Cannot rely on autocmds since they are not executed strictly procedurally.
  -- Might also be related to nested autocmds.
  -- This is not idempotent though, issue?
  resession.add_hook("pre_load", function()
    detach()
  end)

  -- Add extension for save/restore of unsaved buffers
  resession.load_extension("continuity", {})

  -- Ensure we save the current autosession before leaving neovim
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      save()
    end,
    group = autosave_group,
  })
end

local function initial_load()
  -- First, check if we should setup at all.
  -- We don't want to do that if we're running headless or were invoked
  -- with path arguments that were not a single directory.
  -- We also don't want to run if we're running as a pager, but that
  -- detection relies on an event that hasn't been fired yet.
  if util.is_headless() then
    return
  end
  local effective_cwd = util.cwd()
  if not effective_cwd then
    return
  end

  local init_group = vim.api.nvim_create_augroup("ContinuityInit", { clear = true })

  -- This event is triggered before VimEnter and indicates we're running as a pager
  vim.api.nvim_create_autocmd("StdinReadPre", {
    callback = function()
      vim.g._is_pager = true
    end,
    group = init_group,
  })

  -- The actual loading happens on VimEnter.
  -- This loads a session for effective_cwd and creates other
  -- session management hooks.
  vim.api.nvim_create_autocmd("VimEnter", {
    callback = function()
      -- Don't load if we're in pager mode
      if vim.g._is_pager then
        return
      end
      local autosession = render_autosession_context(effective_cwd)
      if not autosession then
        return
      end
      create_hooks()
      load(autosession)
    end,
    group = init_group,
    nested = true, -- otherwise the focused buffer is not initialized correctly
  })
end

---@param opts Continuity.UserConfig?
local function setup(opts)
  config.setup(opts)
  initial_load()
end

local function get_info()
  return vim.deepcopy(_current_session or {})
end

return {
  save = save,
  load = load,
  detach = detach,
  setup = setup,
  save_modified_buffers = save_modified_buffers,
  restore_modified_buffers = restore_modified_buffers,
  restore_modified_buffer = restore_modified_buffer,
  get_info = get_info,
}

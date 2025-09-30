local Config = require("continuity.config")
local Session = require("continuity.core.manager")
local util = require("continuity.util")

--- Interactive API, compatible with stevearc/resession.nvim.
---@class continuity.core
local M = {}

local function get_save_name(tab_scoped)
  -- Try to default to the current session
  info = Session.get_current_data()
  if info and not not info.tabnr == tab_scoped then
    return info.name
  end
  local name
  vim.ui.input({ prompt = "Session name" }, function(selected)
    name = selected
  end)
  return name
end

--- Save the current global state to disk
---@param name? string Name of the session
---@param opts? continuity.SaveOpts
function M.save(name, opts)
  name = name or get_save_name(false)
  if not name then
    return
  end
  Session.save(name, opts)
end

--- Save the state of the current tabpage to disk
---@param name? string Name of the tabpage session. If not provided, will prompt user for session name
---@param opts? continuity.SaveOpts
function M.save_tab(name, opts)
  name = name or get_save_name(true)
  if not name then
    return
  end
  Session.save_tab(name, opts)
end

M.save_all = Session.save_all

---@param opts? continuity.LoadOpts
local function get_load_name(opts)
  local sessions = Session.list({ dir = opts and opts.dir })
  if vim.tbl_isempty(sessions) then
    vim.notify("No saved sessions", vim.log.levels.WARN)
    return
  end
  local select_opts = { kind = "resession_load", prompt = "Load session" }
  if Config.load.detail then
    local session_data = {}
    for _, session_name in ipairs(sessions) do
      local filename =
        util.path.get_session_file(session_name, opts and opts.dir or Config.session.dir)
      local data = util.path.load_json_file(filename)
      session_data[session_name] = data
    end
    select_opts.format_item = function(session_name)
      local data = session_data[session_name]
      local formatted = session_name
      if data then
        if data.tab_scoped then
          local tab_cwd = data.tabs[1].cwd
          formatted = formatted .. string.format(" (tab) [%s]", util.path.shorten_path(tab_cwd))
        else
          formatted = formatted .. string.format(" [%s]", util.path.shorten_path(data.global.cwd))
        end
      end
      return formatted
    end
  end
  local name
  vim.ui.select(sessions, select_opts, function(selected)
    name = selected
  end)
  return name
end

--- Load a session
---@param name? string
---@param opts? continuity.LoadOpts
---    attach? boolean Stay attached to session after loading (default true)
---    reset? boolean|"auto" Close everything before loading the session (default "auto")
---    silence_errors? boolean Don't error when trying to load a missing session
---    dir? string Name of directory to load from (overrides config.dir)
---@note
--- The default value of `reset = "auto"` will reset when loading a normal session, but _not_ when
--- loading a tab-scoped session.
function M.load(name, opts)
  ---@cast opts continuity.LoadOpts
  name = name or get_load_name(opts)
  if not name then
    return
  end
  Session.load(name, opts)
end

-- M.get_current = Manager.get_current
-- M.get_current_data = Manager.get_current_data
M.detach = Session.detach
M.list = Session.list

local function get_delete_name(opts)
  local sessions = Session.list({ dir = opts and opts.dir })
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
end

--- Delete a saved session
---@param name? string Name of the session. If not provided, prompt for session to delete
---@param opts? continuity.DeleteOpts
function M.delete(name, opts)
  name = name or get_delete_name(opts)
  if not name then
    return
  end
  Session.delete(name, opts)
end

local autosave_group
function M.setup()
  autosave_group = vim.api.nvim_create_augroup("ContinuityAutosave", { clear = true })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = autosave_group,
    callback = function()
      -- Trigger detach, which in turn triggers autosave for sessions that have it enabled.
      M.detach(nil, "quit")
    end,
  })
end

return util.lazy_setup_wrapper(M)

local Config = require("continuity.config")
local util = require("continuity.util")

local lazy_require = util.lazy_require
local Buf = lazy_require("continuity.core.buf")
local Ext = lazy_require("continuity.core.ext")
local Session = lazy_require("continuity.core.session")
local log = lazy_require("continuity.log")

---@diagnostic disable-next-line: deprecated
local uv = vim.uv or vim.loop

local M = {}

local current_session ---@type string?
local tab_sessions = {} ---@type table<continuity.TabNr, string?>
local session_configs = {} ---@type table<string, {dir: string, modified?: boolean}?>

local function remove_tabpage_session(name)
  for k, v in pairs(tab_sessions) do
    if v == name then
      tab_sessions[k] = nil
      break
    end
  end
end

--- Save the current global or tabpage state to a named session.
---@param name string The name of the session
---@param opts resession.SaveOpts
---@param target_tabpage? continuity.TabNr Instead of saving everything, only save the current tabpage
local function save(name, opts, target_tabpage)
  if Session.is_loading() then
    log.warn("Save triggered while still loading session. Skipping save.")
    return
  end
  log.fmt_debug(
    "Saving %s session %s with opts %s",
    target_tabpage and "tab" or "global",
    name,
    opts
  )
  local filename = util.path.get_session_file(name, opts.dir or Config.session.dir)
  Ext.dispatch("pre_save", name, opts, target_tabpage)
  local session = Session.snapshot(target_tabpage)
  local state_dir = vim.fs.joinpath(util.path.get_session_dir(opts.dir or Config.session.dir), name)
  if opts.modified then
    session.modified = Buf.save_modified(state_dir)
  else
    -- Forget all saved changes later
    vim.schedule(function()
      Buf.clean_modified(state_dir, {})
    end)
  end
  util.path.write_json_file(filename, session)
  if opts.notify then
    vim.notify(string.format('Saved session "%s"', name))
  end
  if opts.attach then
    session_configs[name] = {
      dir = opts.dir or Config.session.dir,
      modified = opts.modified,
    }
  end
  Ext.dispatch("post_save", name, opts, target_tabpage)
  -- FIXME: unsure if detach/attach logic is sound, this is inherited, but assembled during refactoring
  -- * Afaict it's sound as long as global and tabpage sessions are kept separate,
  --   meaning loading a tabpage session and then saving global state turns a tabpage
  --   into a global session and vice versa
  -- * I think it might make sense to be able to embed tabpage sessions into global ones,
  --   which would mean this handling needs to be modified
  if target_tabpage then
    current_session = nil
    remove_tabpage_session(name) -- this avoids name clashes afaict
  else
    tab_sessions = {}
  end
  if opts.attach then
    if target_tabpage then
      tab_sessions[target_tabpage] = name
    else
      current_session = name
    end
  else
    if target_tabpage then
      tab_sessions[target_tabpage] = nil
    else
      current_session = nil
    end
  end
end

--- Save the current global state to disk
---@param name string Name of the session
---@param opts? resession.SaveOpts
function M.save(name, opts)
  opts = vim.tbl_extend("keep", opts or {}, {
    notify = true,
    attach = true,
  })
  save(name, opts)
end

--- Save the state of the current tabpage to disk
---@param name string Name of the tabpage session.
---@param opts? resession.SaveOpts
function M.save_tab(name, opts)
  opts = vim.tbl_extend("keep", opts or {}, {
    notify = true,
    attach = true,
  })
  save(name, opts, vim.api.nvim_get_current_tabpage())
end

--- Save all current sessions to disk
---@param opts? resession.SaveAllOpts
function M.save_all(opts)
  ---@type resession.SaveOpts
  opts = vim.tbl_extend("keep", opts or {}, {
    notify = true,
  })
  opts.attach = true
  if current_session then
    save(
      current_session,
      vim.tbl_extend("keep", opts, session_configs[current_session] --[[@as table]])
    )
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
      save(name, vim.tbl_extend("keep", opts, session_configs[name] --[[@as table]]), tabpage)
    end
  end
end

--- Load a session
---@param name string
---@param opts? resession.LoadOpts
---    attach? boolean Stay attached to session after loading (default true)
---    reset? boolean|"auto" Close everything before loading the session (default "auto")
---    silence_errors? boolean Don't error when trying to load a missing session
---    dir? string Name of directory to load from (overrides config.dir)
---@note
--- The default value of `reset = "auto"` will reset when loading a normal session, but _not_ when
--- loading a tab-scoped session.
function M.load(name, opts)
  opts = vim.tbl_extend("keep", opts or {}, {
    reset = "auto",
    attach = true,
  })
  ---@cast opts resession.LoadOpts
  local filename = util.path.get_session_file(name, opts.dir or Config.session.dir)
  local session = util.path.load_json_file(filename)
  if not session then
    if not opts.silence_errors then
      error(string.format('Could not find session "%s"', filename))
    end
    return
  end
  log.fmt_trace("Loading session %s. Data: %s", name, session)
  if opts.reset == "auto" then
    opts.reset = not session.tab_scoped
  end
  if opts.modified == nil then
    opts.modified = not not session.modified
  end
  Ext.dispatch("pre_load", name, opts)
  local state_dir = vim.fs.joinpath(util.path.get_session_dir(opts.dir or Config.session.dir), name)
  Session.restore(session, { reset = opts.reset, state_dir = state_dir, modified = opts.modified })
  current_session = nil
  if opts.reset then
    tab_sessions = {}
  end
  remove_tabpage_session(name)
  if opts.attach then
    if session.tab_scoped then
      tab_sessions[vim.api.nvim_get_current_tabpage()] = name
    else
      ---@diagnostic disable-next-line: unused
      current_session = name
    end
    session_configs[name] = {
      dir = opts.dir or Config.session.dir,
      modified = opts.modified,
    }
  end
  Ext.dispatch("post_load", name, opts)
end

--- Get the name of the current session
---@return string?
function M.get_current()
  local tabpage = vim.api.nvim_get_current_tabpage()
  return tab_sessions[tabpage] or current_session
end

--- Get information about the current session
---@return resession.SessionInfo?
function M.get_current_session_info()
  local session = M.get_current()
  if not session then
    return nil
  end
  local save_dir = assert(session_configs[session]).dir
  return {
    name = session,
    dir = save_dir,
    tab_scoped = tab_sessions[vim.api.nvim_get_current_tabpage()] ~= nil,
  }
end

--- Detach from the current session
function M.detach()
  current_session = nil
  local tabpage = vim.api.nvim_get_current_tabpage()
  tab_sessions[tabpage] = nil
end

--- List all available saved sessions
---@param opts? resession.ListOpts
---@return string[]
function M.list(opts)
  opts = opts or {}
  local session_dir = util.path.get_session_dir(opts.dir or Config.session.dir)
  if not util.path.exists(session_dir) then
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
  if Config.load.order == "filename" then
    -- Sort by filename
    table.sort(ret)
  elseif Config.load.order == "modification_time" then
    -- Sort by modification_time
    local default = { mtime = { sec = 0 } }
    table.sort(ret, function(a, b)
      local file_a = uv.fs_stat(session_dir .. "/" .. a .. ".json") or default
      local file_b = uv.fs_stat(session_dir .. "/" .. b .. ".json") or default
      return file_a.mtime.sec > file_b.mtime.sec
    end)
  elseif Config.load.order == "creation_time" then
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

--- Delete a saved session
---@param name string Name of the session. If not provided, prompt for session to delete
---@param opts? resession.DeleteOpts
function M.delete(name, opts)
  opts = vim.tbl_extend("keep", opts or {}, {
    notify = true,
  })
  local filename = util.path.get_session_file(name, opts.dir or Config.session.dir)
  if util.path.delete_file(filename) then
    if opts.notify then
      vim.notify(string.format('Deleted session "%s"', name))
    end
  else
    error(string.format('No session "%s"', filename))
  end
  if current_session == name then
    ---@diagnostic disable-next-line: unused
    current_session = nil
  end
  remove_tabpage_session(name)
end

return M

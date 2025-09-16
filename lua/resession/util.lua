local config = require("resession.config")
local M = {}

---@type boolean?
local seeded
local uuid_v4_template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"

---@type table<string, resession.Extension?>
local ext_cache = {}

--- Get the scope of an option. Note: Does not work for the only tabpage-scoped one (cmdheight).
---@param opt string
---@return 'buf'|'win'|'global'
local function get_option_scope(opt)
  ---@diagnostic disable-next-line: unnecessary-if
  -- This only exists in nvim-0.9
  if vim.api.nvim_get_option_info2 then
    return vim.api.nvim_get_option_info2(opt, {}).scope
  else
    ---@diagnostic disable-next-line: redundant-parameter, deprecated
    return vim.api.nvim_get_option_info(opt).scope
  end
end

--- Attempt to load an extension.
---@param name string The name of the extension to fetch.
---@return resession.Extension?
M.get_extension = function(name)
  if ext_cache[name] then
    return ext_cache[name]
  end
  local has_ext, ext = pcall(require, string.format("resession.extensions.%s", name))
  if has_ext then
    ---@cast ext resession.Extension
    if ext.config then
      local ok, err = pcall(ext.config, config.extensions[name])
      if not ok then
        vim.notify_once(
          string.format('Error configuring resession extension "%s": %s', name, err),
          vim.log.levels.ERROR
        )
        return
      end
    end
    ---@diagnostic disable-next-line: undefined-field
    if ext.on_load then
      -- TODO maybe add some deprecation notice in the future
      ---@diagnostic disable-next-line: undefined-field
      ext.on_post_load = ext.on_load
    end
    ext_cache[name] = ext
    return ext
  else
    vim.notify_once(string.format('[resession] Missing extension "%s"', name), vim.log.levels.WARN)
  end
end

--- Return all global-scoped options.
---@return table<string, any>
M.save_global_options = function()
  local ret = {}
  for _, opt in ipairs(config.options) do
    if get_option_scope(opt) == "global" then
      ret[opt] = vim.go[opt]
    end
  end
  return ret
end

--- Return all window-scoped options of a window buffer.
---@param winid resession.WinID The window number to save options for.
---@return table<string, any>
M.save_win_options = function(winid)
  local ret = {}
  for _, opt in ipairs(config.options) do
    if get_option_scope(opt) == "win" then
      ret[opt] = vim.wo[winid][opt]
    end
  end
  return ret
end

--- Return all buffer-scoped options of a target buffer.
---@param bufnr resession.BufNr The buffer number to save options for.
---@return table<string, any>
M.save_buf_options = function(bufnr)
  local ret = {}
  for _, opt in ipairs(config.options) do
    if get_option_scope(opt) == "buf" then
      ret[opt] = vim.bo[bufnr][opt]
    end
  end
  return ret
end

--- Return all tab-scoped options. Must be called with the target tabpage being the active one.
---@diagnostic disable-next-line: unused
---@param tabnr resession.TabNr Unused.
---@return table<string, any>
M.save_tab_options = function(tabnr)
  local ret = {}
  -- 'cmdheight' is the only tab-local option, but the scope from nvim_get_option_info is incorrect
  -- since there's no way to fetch a tabpage-local option, we rely on this being called from inside
  -- the relevant tabpage
  if vim.tbl_contains(config.options, "cmdheight") then
    ret.cmdheight = vim.o.cmdheight
  end
  return ret
end

--- Restore global-scoped options.
---@param opts table<string, any> The options to apply.
M.restore_global_options = function(opts)
  for opt, val in pairs(opts) do
    if get_option_scope(opt) == "global" then
      vim.go[opt] = val
    end
  end
end

--- Restore window-scoped options.
---@param winid resession.WinID The window number to apply the option to.
---@param opts table<string, any> The options to apply.
M.restore_win_options = function(winid, opts)
  for opt, val in pairs(opts) do
    if get_option_scope(opt) == "win" then
      vim.api.nvim_set_option_value(opt, val, { scope = "local", win = winid })
    end
  end
end

--- Restore buffer-scoped options.
---@param bufnr integer The buffer number to apply the option to.
---@param opts table<string, any> The options to apply.
M.restore_buf_options = function(bufnr, opts)
  for opt, val in pairs(opts) do
    if get_option_scope(opt) == "buf" then
      vim.bo[bufnr][opt] = val
    end
  end
end

--- Restore tab-scoped options.
---@param opts table<string, any>
M.restore_tab_options = function(opts)
  -- 'cmdheight' is the only tab-local option. See save_tab_options
  if opts.cmdheight then
    -- empirically, this seems to only set the local tab value
    vim.o.cmdheight = opts.cmdheight
  end
end

--- Get the path to the directory that stores session files.
---@param dirname? string
---@return string
M.get_session_dir = function(dirname)
  local files = require("resession.files")
  return files.get_stdpath_filename("data", dirname or config.dir)
end

--- Get the path to the file that stores a saved session.
---@param name string The name of the session
---@param dirname? string
---@return string
M.get_session_file = function(name, dirname)
  local files = require("resession.files")
  local filename = string.format("%s.json", name:gsub(files.sep, "_"):gsub(":", "_"))
  return files.join(M.get_session_dir(dirname), filename)
end

--- Decide whether to include a buffer.
---@param tabpage? resession.TabNr When saving a tab-scoped session, the tab number.
---@param bufnr resession.BufNr The buffer to check for inclusion
---@param tabpage_bufs table<resession.BufNr, true?> When saving a tab-scoped session, the list of buffers that are displayed in the tabpage.
M.include_buf = function(tabpage, bufnr, tabpage_bufs)
  if not config.buf_filter(bufnr) then
    return false
  end
  if not tabpage then
    return true
  end
  return tabpage_bufs[bufnr] or config.tab_buf_filter(tabpage, bufnr)
end

--- Given a path, replace $HOME with ~ if present.
---@param path string The path to shorten
---@return string
M.shorten_path = function(path)
  local home = os.getenv("HOME")
  if not home then
    return path
  end
  local idx, chars = string.find(path, home)
  if idx == 1 then
    ---@cast chars integer
    return "~" .. string.sub(path, idx + chars)
  else
    return path
  end
end

--- Trigger a `User` event
---@param event string The event name to be emitted
M.event = function(event)
  local emit_event = function()
    vim.api.nvim_exec_autocmds("User", { pattern = event, modeline = false })
  end
  vim.schedule(emit_event)
end

--- Generate a UUID for a buffer.
---@return resession.BufUUID
M.generate_uuid = function()
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

--- List all untitled buffers using bufnr and uuid.
---@return {buf: resession.BufNr, uuid: resession.BufUUID?}[]
local function list_untitled_buffers()
  local res = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf) == "" then
      table.insert(res, { buf = buf, uuid = vim.b[buf].resession_uuid })
    end
  end
  return res
end

--- Ensure a specific buffer exists (represented by file path or UUID) and has any UUID.
--- File path: Ensure the file is loaded into a buffer and has any UUID. If it does not, assign it the specified one.
--- Unnamed: Ensure an unnamed buffer with the specified UUID exists. If not, create a new unnamed buffer and assign the specified UUID.
---@param name string The path of the buffer or the empty string ("") for unnamed buffers.
---@param uuid? resession.BufUUID The UUID the buffer should have.
---@return integer The buffer ID of the specified buffer.
M.ensure_buf = function(name, uuid)
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
  vim.b[bufnr].resession_uuid = vim.b[bufnr].resession_uuid or uuid or M.generate_uuid()
  return bufnr
end

--- Ensure the active tabpage is a clean one.
function M.open_clean_tab()
  -- Detect if we're already in a "clean" tab
  -- (one window, and one empty scratch buffer)
  if #vim.api.nvim_tabpage_list_wins(0) == 1 then
    if vim.api.nvim_buf_get_name(0) == "" then
      local lines = vim.api.nvim_buf_get_lines(0, -1, 2, false)
      if vim.tbl_isempty(lines) then
        vim.bo.buflisted = false
        vim.bo.bufhidden = "wipe"
        return
      end
    end
  end
  vim.cmd.tabnew()
end

--- Force-close all tabs, windows and unload all buffers.
function M.close_everything()
  local is_floating_win = vim.api.nvim_win_get_config(0).relative ~= ""
  if is_floating_win then
    -- Go to the first window, which will not be floating
    vim.cmd.wincmd({ args = { "w" }, count = 1 })
  end

  local scratch = vim.api.nvim_create_buf(false, true)
  vim.bo[scratch].bufhidden = "wipe"
  vim.api.nvim_win_set_buf(0, scratch)
  vim.bo[scratch].buftype = ""
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[bufnr].buflisted then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end
  vim.cmd.tabonly({ mods = { emsg_silent = true } })
  vim.cmd.only({ mods = { emsg_silent = true } })
end

--- Run a function in a specific eventignore/shortmess context.
---@generic T
---@param evt string The o:eventignore to use for the inner context
---@param mess string The o:shortmess to use for the inner context
---@param inner fun(): T
---@return T
function M.suppress(evt, mess, inner)
  local eventignore = vim.o.eventignore
  vim.o.eventignore = evt
  local shortmess = vim.o.shortmess
  vim.o.shortmess = mess
  local ret = inner()
  vim.o.eventignore = eventignore
  vim.o.shortmess = shortmess
  return ret
end

return M

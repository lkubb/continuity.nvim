local config = require("resession.config")
local M = {}

local seeded
local uuid_v4_template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"

---@param opt string
---@return string
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

local ext_cache = {}
---@param name string
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

---@param winid integer
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

---@param bufnr integer
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

---@diagnostic disable-next-line: unused
---@param bufnr integer
---@return table<string, any>
M.save_tab_options = function(bufnr)
  local ret = {}
  -- 'cmdheight' is the only tab-local option, but the scope from nvim_get_option_info is incorrect
  -- since there's no way to fetch a tabpage-local option, we rely on this being called from inside
  -- the relevant tabpage
  if vim.tbl_contains(config.options, "cmdheight") then
    ret.cmdheight = vim.o.cmdheight
  end
  return ret
end

---@param opts table<string, any>
M.restore_global_options = function(opts)
  for opt, val in pairs(opts) do
    if get_option_scope(opt) == "global" then
      vim.go[opt] = val
    end
  end
end

---@param winid integer
---@param opts table<string, any>
M.restore_win_options = function(winid, opts)
  for opt, val in pairs(opts) do
    if get_option_scope(opt) == "win" then
      vim.api.nvim_set_option_value(opt, val, { scope = "local", win = winid })
    end
  end
end

---@param bufnr integer
---@param opts table<string, any>
M.restore_buf_options = function(bufnr, opts)
  for opt, val in pairs(opts) do
    if get_option_scope(opt) == "buf" then
      vim.bo[bufnr][opt] = val
    end
  end
end

---@param opts table<string, any>
M.restore_tab_options = function(opts)
  -- 'cmdheight' is the only tab-local option. See save_tab_options
  if opts.cmdheight then
    -- empirically, this seems to only set the local tab value
    vim.o.cmdheight = opts.cmdheight
  end
end

---@param dirname? string
---@return string
M.get_session_dir = function(dirname)
  local files = require("resession.files")
  return files.get_stdpath_filename("data", dirname or config.dir)
end

---@param name string The name of the session
---@param dirname? string
---@return string
M.get_session_file = function(name, dirname)
  local files = require("resession.files")
  local filename = string.format("%s.json", name:gsub(files.sep, "_"):gsub(":", "_"))
  return files.join(M.get_session_dir(dirname), filename)
end

M.include_buf = function(tabpage, bufnr, tabpage_bufs)
  if not config.buf_filter(bufnr) then
    return false
  end
  if not tabpage then
    return true
  end
  return tabpage_bufs[bufnr] or config.tab_buf_filter(tabpage, bufnr)
end

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
---@return string
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
---@return {buf: number, uuid: string?}[]
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
---@param uuid? string The UUID the buffer should have.
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

return M

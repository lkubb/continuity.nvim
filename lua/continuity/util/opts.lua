---@class continuity.util.Opts
local M = {}

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

--- Return all global-scoped options in a list of any options.
---@param opts string[] A list of options to fetch current values for if they are global-scoped
---@return table<string, any>
function M.get_global(opts)
  local ret = {}
  for _, opt in ipairs(opts) do
    if get_option_scope(opt) == "global" then
      ret[opt] = vim.go[opt]
    end
  end
  return ret
end

--- Return all window-scoped options of a target window in a list of any options.
---@param winid continuity.WinID The window number to return options for.
---@param opts string[] A list of options to fetch current values for if they are window-scoped
---@return table<string, any>
function M.get_win(winid, opts)
  local ret = {}
  for _, opt in ipairs(opts) do
    if get_option_scope(opt) == "win" then
      ret[opt] = vim.wo[winid][opt]
    end
  end
  return ret
end

--- Return all buffer-scoped options of a target buffer in a list of any options.
---@param bufnr continuity.BufNr The buffer number to return options for.
---@param opts string[] A list of options to fetch current values for if they are buffer-scoped
---@return table<string, any>
function M.get_buf(bufnr, opts)
  local ret = {}
  for _, opt in ipairs(opts) do
    if get_option_scope(opt) == "buf" then
      ret[opt] = vim.bo[bufnr][opt]
    end
  end
  return ret
end

--- Return all tab-scoped options of the current (!) tabpage.
--- Note: Must be called with the target tabpage being the active one.
---@diagnostic disable-next-line: unused
---@param tabnr continuity.TabNr Unused.
---@param opts string[] A list of options to fetch current values for if they are tab-scoped
---@return table<string, any>
function M.get_tab(tabnr, opts)
  local ret = {}
  -- 'cmdheight' is the only tab-local option, but the scope from nvim_get_option_info is incorrect
  -- since there's no way to fetch a tabpage-local option, we rely on this being called from inside
  -- the relevant tabpage
  if vim.tbl_contains(opts, "cmdheight") then
    ret.cmdheight = vim.o.cmdheight
  end
  return ret
end

--- Restore global-scoped options.
---@param opts table<string, any> The options to apply.
function M.restore_global(opts)
  for opt, val in pairs(opts) do
    if get_option_scope(opt) == "global" then
      vim.go[opt] = val
    end
  end
end

--- Restore window-scoped options.
---@param winid continuity.WinID The window number to apply the option to.
---@param opts table<string, any> The options to apply.
function M.restore_win(winid, opts)
  for opt, val in pairs(opts) do
    if get_option_scope(opt) == "win" then
      vim.api.nvim_set_option_value(opt, val, { scope = "local", win = winid })
    end
  end
end

--- Restore buffer-scoped options.
---@param bufnr integer The buffer number to apply the option to.
---@param opts table<string, any> The options to apply.
function M.restore_buf(bufnr, opts)
  for opt, val in pairs(opts) do
    if get_option_scope(opt) == "buf" then
      vim.bo[bufnr][opt] = val
    end
  end
end

--- Restore tab-scoped options.
---@param opts table<string, any>
function M.restore_tab(opts)
  -- 'cmdheight' is the only tab-local option. See save_tab_options
  if opts.cmdheight then
    -- empirically, this seems to only set the local tab value
    vim.o.cmdheight = opts.cmdheight
  end
end

--- Run a function with specific opts set and restore the previous state after.
--- Accepts options of all scopes, but ensure the targets are still valid after the function has finished.
---@generic T
---@param overrides table<string, any> A mapping of opts to override to their override values
---@param inner fun(): T The function to execute with the opt overrides
---@return T
function M.with(overrides, inner)
  local bak = {}
  for opt, ovrr in pairs(overrides) do
    bak[opt] = vim.o[opt]
    vim.o[opt] = ovrr
  end
  local ok, ret = pcall(inner)
  for opt, init in pairs(bak) do
    vim.o[opt] = init
  end
  if not ok then
    error(ret)
  end
  ---@cast ret -string
  return ret
end

return M

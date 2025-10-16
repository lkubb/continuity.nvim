---@class continuity.util.opts
local M = {}

---@using continuity.core

--- Get the scope of an option. Note: Does not work for the only tabpage-scoped one (cmdheight).
---@param opt string Name of the option
---@return "buf"|"win"|"global" option_scope #
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
---@return table<string, any> global_opts #
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
---@param winid WinID Window ID to return options for.
---@param opts string[] #
---   List of options to fetch current values for (if they are window-scoped).
---   Options of other scopes are ignored.
---@return table<string, any> win_opts #
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
---@param bufnr BufNr Buffer number to return options for.
---@param opts string[] #
---   List of options to fetch current values for (if they are buffer-scoped).
---   Options of other scopes are ignored.
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
---@param tabnr TabNr Unused.
---@param opts string[] #
---   List of options to fetch current values for (if they are tab-scoped).
---   Options of other scopes are ignored.
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
---@param opts table<string, any> #
---   Mapping of options to values to apply.
---   Only those deemed globally scoped are applied, others are ignored.
function M.restore_global(opts)
  for opt, val in pairs(opts) do
    if get_option_scope(opt) == "global" then
      vim.go[opt] = val
    end
  end
end

--- Restore window-scoped options.
---@param winid WinID Window ID to apply the options to.
---@param opts table<string, any> #
---   Mapping of options to values to apply.
---   Only those deemed window-scoped are applied, others are ignored.
function M.restore_win(winid, opts)
  for opt, val in pairs(opts) do
    if get_option_scope(opt) == "win" then
      vim.api.nvim_set_option_value(opt, val, { scope = "local", win = winid })
    end
  end
end

--- Restore buffer-scoped options.
---@param bufnr integer Buffer number to apply the options to.
---@param opts table<string, any> #
---   Mapping of options to values to apply.
---   Only those deemed buffer-scoped are applied, others are ignored.
function M.restore_buf(bufnr, opts)
  for opt, val in pairs(opts) do
    if get_option_scope(opt) == "buf" then
      vim.bo[bufnr][opt] = val
    end
  end
end

--- Restore tab-scoped options.
--- Note: Must be run with the target tab as active tab.
---@param opts table<string, any> #
---   Mapping of options to values to apply.
---   Only those deemed tab-scoped are applied, others are ignored.
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
---@param overrides table<string, any> Mapping of opts to override to their override values
---@param inner fun(): T... Function to execute while opt overrides are active
---@return T... #
---   Variadic returns of inner function
function M.with(overrides, inner)
  local bak = {}
  for opt, ovrr in pairs(overrides) do
    bak[opt] = vim.o[opt]
    vim.o[opt] = ovrr
  end
  return require("continuity.util").try_finally(inner, function()
    for opt, init in pairs(bak) do
      vim.o[opt] = init
    end
  end)
end

--- Search through tables in descending priority for a non-nil key or return default.
--- Note: This being in the `opts` namespace does not carry any semantic meaning, it does not
--- operate on neovim options.
---@generic Opts: table, Key, Default
---@param name std.ConstTpl<Key> Key to look for
---@param default Default Default value if not found
---@param ... Opts... Option tables to search in (descending priority)
---@return std.RawGet<Opts, Key>|Default opt_or_default #
---   Option value in the first matching table or default value, if not found
function M.coalesce(name, default, ...)
  for _, src in ipairs({ ... }) do
    if src[name] ~= nil then
      return src[name]
    end
  end
  return default
end

--- Search through tables in descending priority for a non-nil key. If the result is `auto`,
--- treats it the same as a missing key and returns the default.
--- Note: This being in the `opts` namespace does not carry any semantic meaning, it does not
--- operate on neovim options.
---@generic Opts: table, Key, Default, AutoMapped
---@param name std.ConstTpl<Key> Key to look for
---@param default AutoMapped Value `auto` should be mapped to
---@param ... Opts... Option tables to search in (descending priority)
---@return std.RawGet<Opts, Key>|AutoMapped #
---   Option value in the first matching table (or the value `auto` is mapped to, if it was auto)
---   or the value `auto` is mapped to if not found (`auto` is assumed to be default).
function M.coalesce_auto(name, default, ...)
  local res = M.coalesce(name, "auto", ...)
  if res == "auto" then
    return default
  end
  return res
end

return M

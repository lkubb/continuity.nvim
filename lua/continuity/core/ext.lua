local Config = require("continuity.config")

local hooks = setmetatable({
  ---@type continuity.LoadHook[]
  pre_load = {},
  ---@type continuity.LoadHook[]
  post_load = {},
  ---@type continuity.SaveHook[]
  pre_save = {},
  ---@type continuity.SaveHook[]
  post_save = {},
}, {
  __index = function(_, key)
    error(string.format('Unrecognized hook "%s"', key))
  end,
})

-- FIXME: IIRC autocmds are only triggered after the respective logic has finished running,
--        unless we schedule the rest of the logic after triggering hooks (this might not
--        be possible for the loading logic because it should reduce disturbances).
--        This would mean autocmds cannot influence the respective operation and ergo
--        the pre/post distinction in events doesn't make sense. Consider reducing
--        the events to loaded/saved ones on post hooks.

---@type table<resession.Hook, string>
local hook_to_event = {
  pre_load = "ResessionLoadPre",
  post_load = "ResessionLoadPost",
  pre_save = "ResessionSavePre",
  post_save = "ResessionSavePost",
}

local has_setup = false

---@class continuity.core.ext
local M = {}

--- Trigger a `User` event
---@param name string The event name to be emitted
local function event(name)
  local emit_event = function()
    vim.api.nvim_exec_autocmds("User", { pattern = name, modeline = false })
  end
  vim.schedule(emit_event)
end

function M.setup()
  if has_setup then
    return
  end
  for hook, _ in pairs(hooks) do
    ---@diagnostic disable-next-line: param-type-not-match
    M.add_hook(hook, function()
      event(hook_to_event[hook])
    end)
  end
  ---@diagnostic disable-next-line: unused
  has_setup = true
end

--- Add a callback that runs at a specific time
---@param name resession.Hook
---@param callback continuity.LoadHook|continuity.SaveHook
function M.add_hook(name, callback)
  hooks[name][#hooks[name] + 1] = callback
end

--- Remove a hook callback
---@param name resession.Hook
---@param callback continuity.LoadHook|continuity.SaveHook
function M.remove_hook(name, callback)
  local cbs = hooks[name]
  for i, cb in ipairs(cbs) do
    if cb == callback then
      table.remove(cbs, i)
      break
    end
  end
end

--- Load an extension some time after calling setup()
---@param name string Name of the extension
---@param opts table Configuration options for extension
function M.load_extension(name, opts)
  ---@diagnostic disable-next-line: unnecessary-if
  -- config.log is only defined if setup has been run
  if Config.log then
    Config.extensions[name] = opts
    M.get(name)
  elseif vim.g.continuity_config then
    local config = vim.g.continuity_config
    config.extensions = config.extensions or {}
    config.extensions[name] = opts
    vim.g.continuity_config = config
  else
    error(
      "Cannot load extension before setup was called or vim.g.continuity_config was initialized"
    )
  end
end

---@type table<string, continuity.Extension?>
local ext_cache = {}

--- Attempt to load an extension.
---@param name string The name of the extension to fetch.
---@return continuity.Extension?
function M.get(name)
  if ext_cache[name] then
    return ext_cache[name]
  end
  local has_ext, ext = pcall(require, string.format("resession.extensions.%s", name))
  if has_ext then
    ---@cast ext continuity.Extension
    if ext.config then
      local ok, err = pcall(ext.config, Config.extensions[name])
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
    vim.notify_once(string.format('[continuity] Missing extension "%s"', name), vim.log.levels.WARN)
  end
end

--- Call registered hooks for `name`.
---@param name resession.Hook The specific hook to dispatch
---@param ... any Arguments to pass to registered callbacks
function M.dispatch(name, ...)
  for _, cb in ipairs(hooks[name]) do
    cb(...)
  end
end

return M

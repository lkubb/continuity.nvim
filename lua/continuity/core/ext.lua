---@class continuity.core.ext
local M = {}

---@type continuity.log
local log

---@namespace continuity.core.ext
---@using continuity.core

local Config = require("continuity.config")

local hooks = setmetatable({
  ---@type LoadHook[]
  pre_load = {},
  ---@type LoadHook[]
  post_load = {},
  ---@type SaveHook[]
  pre_save = {},
  ---@type SaveHook[]
  post_save = {},
}, {
  __index = function(_, key)
    error(string.format('Unrecognized hook "%s"', key))
  end,
})

-- Autocmds are only triggered after our logic has already finished,
-- meaning that there's no practical distinction between pre/post variants for events.
-- Therefore, we just trigger a general saved/loaded on post hooks.
-- We could make pre/post meaningful by scheduling after the autocmds were triggered,
-- but this could break session loading (especially).
---@type table<Hook, string>
local hook_to_event = {
  post_load = "ContinuityLoaded",
  post_save = "ContinuitySaved",
}

local has_setup = false

--- Trigger a `User` event
---@param name string Event name to be emitted
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
  log = require("continuity.log")
  has_setup = true
end

--- Add a callback that runs at a specific time
---@param name Hook Name of the hook event to attach to
---@param callback LoadHook|SaveHook Hook to attach to hook event
function M.add_hook(name, callback)
  hooks[name][#hooks[name] + 1] = callback
end

--- Remove a hook callback
---@param name Hook Name of the hook event the hook is attached to
---@param callback LoadHook|SaveHook Hook to remove
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

---@type table<string, Extension?>
local ext_cache = {}

--- Attempt to load an extension.
---@param name string Name of the extension to fetch.
---@return Extension? extension Loaded extension module, if found
function M.get(name)
  if ext_cache[name] then
    return ext_cache[name]
  end
  local ns = "continuity"
  if vim.tbl_get(Config.extensions, name, "resession_compat") then
    ns = "resession"
  end
  local compat_fallback
  local has_ext, ext = pcall(require, string.format("%s.extensions.%s", ns, name))
  if not has_ext and ns == "continuity" then
    compat_fallback = true
    has_ext, ext = pcall(require, string.format("resession.extensions.%s", name))
  end
  if not has_ext then
    vim.notify_once(
      string.format(
        '[continuity] Missing extension "%s" in namespace "%s", ensure it is installed. '
          .. "If the namespace is wrong, check the `extensions.%s.resession_compat` setting",
        name,
        ns,
        name
      ),
      vim.log.levels.WARN
    )
    return
  elseif compat_fallback then
    require("continuity.log").warn(
      string.format(
        '[continuity] Missing extension at "continuity.extensions.%s", but found it in "resession.extensions.%s". '
          .. "Ensure you set `extensions.%s.resession_compat` to true to avoid overhead",
        name,
        name,
        name
      )
    )
  end
  ---@cast ext Extension
  if ext.config then
    local ok, err = pcall(ext.config, Config.extensions[name])
    if not ok then
      vim.notify_once(
        string.format('Error configuring continuity extension "%s": %s', name, err),
        vim.log.levels.ERROR
      )
      return
    end
  end
  ---@diagnostic disable-next-line: undefined-field
  if (ns == "resession" or compat_fallback) and ext.on_load then
    -- TODO maybe add some deprecation notice in the future
    ---@diagnostic disable-next-line: undefined-field
    ext.on_post_load = ext.on_load
  end
  ext_cache[name] = ext
  return ext
end

--- Call registered hooks for `name`.
---@overload fun(name: Hook.Load, session_name: string, opts: ext.HookOpts)
---@param name Hook.Save
---@param session_name string
---@param opts HookOpts
---@param target_tabnr? TabNr
function M.dispatch(name, session_name, opts, target_tabnr)
  for _, cb in ipairs(hooks[name]) do
    cb(session_name, opts, target_tabnr)
  end
end

--- Call extension funcs that don't need special handling/don't return a value
---@overload fun(stage_name: "on_pre_load", snapshot: Snapshot, opts: snapshot.Context)
---@overload fun(stage_name: "on_post_load", snapshot: Snapshot, opts: snapshot.Context)
---@overload fun(stage_name: "on_post_bufinit", snapshot: Snapshot, visible_only: boolean)
---@overload fun(stage_name: "on_buf_load", snapshot: Snapshot, bufnr: BufNr)
---@generic T
---@param stage_name "on_pre_load"|"on_post_load"|"on_post_bufinit"|"on_buf_load"
---@param snapshot Snapshot
---@param ... T...
function M.call(stage_name, snapshot, ...)
  for ext_name in pairs(Config.extensions) do
    if snapshot[ext_name] then
      local extmod = M.get(ext_name)
      if extmod and extmod[stage_name] then
        log.fmt_trace(
          "Calling extension %s.%s with data %s",
          ext_name,
          stage_name,
          snapshot[ext_name]
        )
        local ok, err = pcall(extmod[stage_name], snapshot[ext_name], ...)
        if not ok then
          vim.notify(
            string.format("[continuity] Extension %s %s error: %s", ext_name, stage_name, err),
            vim.log.levels.ERROR
          )
        end
      end
    end
  end
end

return M

---@class resession.UserConfig
---@field autosave? resession.UserConfig.autosave Options for automatically saving sessions on a timer
---@field options? string[] Save and restore these options
---@field buf_filter? fun(integer): boolean Custom logic for determining if the buffer should be included
---@field tab_buf_filter? fun(tabpage: integer, bufnr: integer): boolean Custom logic for determining if a buffer should be included in a tab-scoped session
---@field dir? string The name of the directory to store sessions in
---@field load_detail? boolean Show more detail about the sessions when selecting one to load. Disable if it causes lag.
---@field load_order? "modification_time"|"creation_time"|"filename" Session list order
---@field extensions? table<string,any> Configuration for extensions
---@field log? resession.UserConfig.log Configuration for plenary.log

---@class resession.UserConfig.autosave
---@field enabled? boolean When a session is active, automatically save it in intervals. Defaults to false.
---@field interval? integer Seconds between autosaves
---@field notify? boolean Trigger a notification when autosaving. Defaults to true.

---@class resession.UserConfig.log
---@field level? "trace"|"debug"|"info"|"warn"|"error"|"fatal" The minimum level to log for
---@field use_console? "async"|"sync"|false Print logs to neovim console. Defaults to async.
---@field use_file? boolean Print logs to logfile. Defaults to true.

-- Until https://github.com/EmmyLuaLs/emmylua-analyzer-rust/issues/328 is resolved,
-- need to keep UserConfig and config with defaults in sync.

---@class resession.Config: resession.UserConfig
---@field autosave resession.Config.autosave
---@field options string[]
---@field buf_filter fun(integer): boolean
---@field tab_buf_filter fun(tabpage: integer, bufnr: integer): boolean
---@field dir string
---@field load_detail boolean
---@field load_order "modification_time"|"creation_time"|"filename"
---@field extensions table<string,any>
---@field log resession.Config.log

---@class resession.Config.autosave: resession.UserConfig.autosave
---@field enabled boolean
---@field interval integer
---@field notify boolean

---@class resession.Config.log: resession.UserConfig.log
---@field level "trace"|"debug"|"info"|"warn"|"error"|"fatal"
---@field use_console "async"
---@field use_file boolean

---@class resession.config: resession.Config
local M = {}

---@diagnostic disable-next-line: deprecated
local uv = vim.uv or vim.loop

---@type resession.Config
local default_config = {
  autosave = {
    enabled = false,
    interval = 60,
    notify = true,
  },
  options = {
    "binary",
    "bufhidden",
    "buflisted",
    "cmdheight",
    "diff",
    "filetype",
    "modifiable",
    "previewwindow",
    "readonly",
    "scrollbind",
    "winfixheight",
    "winfixwidth",
  },
  buf_filter = require("resession").default_buf_filter,
  ---@diagnostic disable-next-line: unused
  tab_buf_filter = function(tabpage, bufnr)
    return true
  end,
  dir = "session",
  load_detail = true,
  load_order = "modification_time",
  extensions = {
    quickfix = {},
  },
  log = {
    level = "warn",
    use_console = "async",
    use_file = true,
  },
}

---@type uv.uv_timer_t?
local autosave_timer

---@param config resession.UserConfig
M.setup = function(config)
  local resession = require("resession")
  local newconf = vim.tbl_deep_extend("force", default_config, config)

  for k, v in pairs(newconf) do
    M[k] = v
  end

  if autosave_timer then
    autosave_timer:close()
    autosave_timer = nil
  end
  local autosave_group = vim.api.nvim_create_augroup("ResessionAutosave", { clear = true })
  if M.autosave.enabled then
    vim.api.nvim_create_autocmd("VimLeavePre", {
      group = autosave_group,
      callback = function()
        resession.save_all({ notify = false })
      end,
    })
    autosave_timer = assert(uv.new_timer())
    autosave_timer:start(
      M.autosave.interval * 1000,
      M.autosave.interval * 1000,
      vim.schedule_wrap(function()
        resession.save_all({ notify = M.autosave.notify })
      end)
    )
  end
end

return M

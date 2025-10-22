-- There's no way to get the `cmdheight` tabpage-local option
-- for a non-current tabpage. We need to know this value, but
-- session saving should avoid interfering with the UI at all
-- costs. Solution: Keep track of this option for all tabs in
-- a tabpage variable.
local function update_cmdheight_optionset()
  vim.t.continuity_cmdheight_tracker = vim.v.option_new
end

local function update_cmdheight()
  vim.t.continuity_cmdheight_tracker = vim.o.cmdheight
end

local plugin_group = vim.api.nvim_create_augroup("ContinuityPlugin", { clear = true })

vim.api.nvim_create_autocmd("OptionSet", {
  pattern = "cmdheight",
  group = plugin_group,
  desc = "Continuity: Keep track of cmdheight changes",
  -- NOTE: This is called each time switching the current tabpage causes a change in cmdheight.
  callback = update_cmdheight_optionset,
})

vim.api.nvim_create_autocmd("TabNewEntered", {
  group = plugin_group,
  desc = "Continuity: Initialize tracked cmdheight of new tabpage",
  callback = update_cmdheight,
})

vim.api.nvim_create_autocmd("VimEnter", {
  group = plugin_group,
  desc = "Continuity: Initialize tracked cmdheight of initial tabpage",
  callback = update_cmdheight,
})

-- If folke/lazy.nvim is in use, we need to know when it
-- finishes setup to be able to properly restore buffers.
---@cast vim.g.lazy_did_setup boolean?
if vim.g.lazy_did_setup then
  vim.api.nvim_create_autocmd("User", {
    pattern = "VeryLazy",
    callback = function()
      vim.g._continuity_verylazy_done = true
    end,
    once = true,
  })
else
  vim.g._continuity_verylazy_done = true
end

-- Initialize Continuity user command
vim.api.nvim_create_user_command("Continuity", function(params)
  require("continuity.cli").run(params)
end, {
  force = true,
  nargs = "*",
  complete = function(arglead, line)
    return require("continuity.cli").complete(arglead, line)
  end,
})

---@type continuity.auto.InitHandler|boolean
vim.g.continuity_autosession = vim.g.continuity_autosession or false

if vim.g.continuity_autosession then
  local is_pager = false

  -- This event is triggered before VimEnter and indicates we're running as a pager.
  -- Continuity should usually be disabled in that case.
  vim.api.nvim_create_autocmd("StdinReadPre", {
    callback = function()
      is_pager = true
    end,
    group = plugin_group,
    once = true,
  })

  -- The actual loading happens on VimEnter.
  -- This loads a session for effective_cwd and creates other
  -- session management hooks.
  vim.api.nvim_create_autocmd("VimEnter", {
    callback = function()
      ---@type continuity.auto.InitHandler
      local get_cwd
      if type(vim.g.continuity_autosession) == "function" then
        get_cwd = vim.g.continuity_autosession
      else
        get_cwd = function(ctx)
          if ctx.is_headless or ctx.is_pager then
            return false
          end
          return require("continuity.util").auto.cwd_init() or false
        end
      end
      local startup_cwd = get_cwd({
        is_headless = require("continuity.util").auto.is_headless(),
        is_pager = is_pager,
      })
      -- Don't load at all if we're instructed to.
      -- This can be nil, which indicates we shouldn't autoload a session,
      -- but still monitor for directory/branch changes.
      if startup_cwd == false then
        return
      end
      require("continuity.auto").load(startup_cwd)
    end,
    group = plugin_group,
    once = true,
    nested = true, -- otherwise the focused buffer is not initialized correctly
  })
end

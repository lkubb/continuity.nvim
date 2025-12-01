---@type continuity.core.Extension
local M = {}

---@namespace continuity.extensions.neogit
---@using continuity.core

---@class SaveContext
---@field bufnr BufNr
---@field winid WinID
---@field cwd string

---@class BaseView
---@field cwd string Repository path
---@field default_cwd string Last requested repository path (used as default and needs to be restored to avoid confusion)
---@field ft "NeogitStatus"|"NeogitCommitView"

---@class StatusData
---@field fold_state table<string, table>
---@field view_state table<string, integer>

---@class Status: BaseView, StatusData
---@field ft "NeogitStatus"

---@class CommitData
---@field commit_id string
---@field filter? string[]

---@class Commit: BaseView, CommitData
---@field ft "NeogitCommitView"

---@alias View Commit|Status

local neogit ---@module "neogit"
local ngrepo ---@module "neogit.lib.git.repository"

local fts = { "NeogitStatus", "NeogitCommitView" }

function M.is_win_supported(_winid, bufnr)
  return vim.list_contains(fts, vim.bo[bufnr].filetype)
end

---@param ctx SaveContext
---@return StatusData
local function save_status(ctx)
  local buf = require("neogit.buffers.status").instance(ctx.cwd)
  if not buf.buffer then
    -- unfocused, neogit saves this data on the instance
    return {
      fold_state = buf.fold_state,
      view_state = buf.view_state,
    }
  end
  return {
    -- Cannot rely on buffer:cursor_line, it targets the current buffer.
    fold_state = buf.buffer.ui:get_fold_state(),
    view_state = buf.buffer:save_view(),
  }
end

---@return CommitData
local function save_commit()
  local buf = require("neogit.buffers.commit_view").instance
  ---@diagnostic disable-next-line: need-check-nil, undefined-field
  local commit_id, filter = buf.commit_info.commit_arg, buf.item_filter
  return {
    commit_id = commit_id,
    filter = filter,
  }
end

---@param winid WinID
---@return View
function M.save_win(winid)
  ngrepo = ngrepo or require("neogit.lib.git.repository")
  local bufnr = vim.api.nvim_win_get_buf(winid)
  local cwd = vim.api.nvim_win_call(winid, vim.fn.getcwd)
  local ft = vim.bo[bufnr].filetype
  local default_cwd = ngrepo.instance().worktree_root
  local ctx = { bufnr = bufnr, cwd = cwd, winid = winid }
  local sav ---@type View
  if ft == "NeogitStatus" then
    sav = save_status(ctx)
  elseif ft == "NeogitCommitView" then
    sav = save_commit()
  -- elseif ft == "NeogitLogView" then
  --   sav = save_log()
  else
    error("Unsupported view")
  end
  ngrepo.instance(default_cwd) -- reset the default
  sav.cwd, sav.ft, sav.default_cwd = cwd, ft, default_cwd
  return sav
end

---@param config Status
---@param win layout.WinInfo
local function open_status(config, win)
  ---@cast ngrepo NeogitRepo
  local repo = ngrepo.instance(config.cwd)
  local buf = require("neogit.buffers.status").new(
    require("neogit.config").values,
    repo.worktree_root,
    config.cwd
  )
  ---@diagnostic disable-next-line: need-check-nil
  local cursor_line = win.view and win.view.lnum or win.cursor[1]
  buf.fold_state, buf.view_state, buf.cursor_state =
    config.fold_state, config.view_state, cursor_line
  buf:open("replace"):dispatch_refresh()
end

---@param config Commit
local function open_commit(config)
  local buf = require("neogit.buffers.commit_view").new(config.commit_id, config.filter)
  buf:open("replace")
end

---@param winid WinID
---@param config View
---@param win layout.WinInfo
function M.load_win(winid, config, win)
  neogit = neogit or require("neogit")
  ngrepo = ngrepo or require("neogit.lib.git.repository")
  if not neogit.autocmd_group then
    neogit.setup({})
  end
  -- Ensure the correct cwd has been requested last, most views only operate on that.
  ngrepo.instance(config.cwd)
  vim.api.nvim_set_current_win(winid)
  if config.ft == "NeogitStatus" then
    open_status(config, win)
  elseif config.ft == "NeogitCommitView" then
    open_commit(config)
  -- elseif config.ft == "NeogitLogView" then
  --   open_log(config, win)
  else
    error("Unsupported view")
  end
  -- Reset the default repo to the expected one
  ngrepo.instance(config.default_cwd)
end

return M

--- Notes on restoring NeogitLogView:
---
--- Restoring the log view is seriously hard to do, and cannot be done "properly" afaict:
---   * Parameters that created the view are not accessible other than with debug.getupvalue.
---   * We have to guess the action that lead to the view via its `flags` (target spec).
---   * Or, better: Since there is no way to specify the `flags` via an action, we would need to create a custom one
---     which just takes the flags.
---   * Actually opening the view requires popup state. The `neogit.action` API does not allow to recreate
---     everything in there, so we would need to reimplement that API.
--- The following code works, but it
---   1) is very hacky, thus brittle
---   2) is not nearly complete (exception: opened via NeogitLogCurrent)
---   3) cannot specify how to open the view, so it's usually opened in a new tab after a (long) delay.
---      It would need to close the current window.

-- ---@class LogData
--
-- ---@class Log: BaseView, LogData
-- ---@field ft "NeogitLogView"
-- ---@field args string[]
-- ---@field action string
--
-- ---@param config Log
-- ---@param win layout.WinInfo
-- local function open_log(config, win)
--   neogit.action("log", config.action, config.args)()
-- end
--
-- ---@return LogData
-- local function save_log()
--   local buf = require("neogit.buffers.log_view").instance
--   local i = 1
--   local popup, flags, args
--   while i < 10 do
--     local upname, upval = debug.getupvalue(buf.fetch_func, i)
--     if not upname then
--       break
--     end
--     if upname == "popup" then
--       popup = upval
--     elseif upname == "flags" then
--       flags = upval
--     end
--     if popup and flags then
--       break
--     end
--     i = i + 1
--   end
--   if not (popup and flags) then
--     error("Could not determine args/flags for log view")
--   end
--   local action
--   if vim.tbl_isempty(flags) then
--     action = "log_current"
--   elseif #flags == 1 and flags[1] == "HEAD" then
--     action = "log_head"
--   elseif flags[2] == "--branches" then
--     action = "log_local_branches"
--   elseif flags[3] == "--remotes" then
--     action = "log_all_branches"
--   elseif flags[2] == "--all" then
--     action = "log_all_references"
--   else
--     error("Could not determine log type")
--   end
--   return { args = popup:get_arguments(), action = action }
-- end

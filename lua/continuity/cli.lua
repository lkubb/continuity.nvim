---@class continuity.Cli
local M = {}

local continuity = require("continuity")

local funcs = {
  info = continuity.info,
  list = continuity.list,
  load = continuity.load,
  reload = continuity.reload,
  reset = continuity.reset, -- should require bang with unsaved changes?
  reset_project = continuity.reset_project,
}

M.complete = function(arglead, line)
  local words = vim.split(line, "%s+")
  local n = #words

  local matches = {}
  if n == 2 then
    for func, _ in pairs(funcs) do
      -- if not func:match("^[a-z]") then
      --   -- exclude
      if vim.startswith(func, arglead) then
        table.insert(matches, func)
      end
    end
  elseif n > 2 then
    if words[2] == "load" then
      matches = vim.list_extend(matches, funcs.list())
      table.insert(matches, func)
    end
  end
  return matches
end

M.run = function(params)
  func = funcs[params.fargs[1]]
  if not func then
    vim.ui.select(M.complete("", "Continuity "), {}, function(item)
      func = funcs[item]
    end)
    if not func then
      return
    end
  end
  local ret = func()
  if ret then
    vim.notify(vim.inspect(ret))
  end
end

return M

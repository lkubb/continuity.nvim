---@class continuity.cli
local M = {}

local Continuity = require("continuity")

---@type {[keyof continuity]: {func: function, args?: {complete: string[]|function}[], kwargs?: table<string, string[]|function>}}
local funcs = {
  detach = {
    func = Continuity.detach,
    kwargs = {
      reset = { "true", "false" },
      save = { "true", "false" },
    },
  },
  info = {
    func = Continuity.info,
    kwargs = {
      with_snapshot = { "true", "false" },
    },
  },
  list = {
    func = Continuity.list,
    kwargs = {
      cwd = Continuity.list_projects,
    },
  },
  list_projects = {
    func = Continuity.list_projects,
  },
  migrate_projects = {
    func = Continuity.migrate_projects,
  },
  load = {
    func = Continuity.load,
    args = {
      -- This would need to complete directory paths
      { complete = {}, required = true },
    },
    kwargs = {
      attach = { "true", "false" },
      reset = { "true", "false", "auto" },
      detach_save = { "true", "false" },
      modified = { "true", "false", "auto" },
      autosave_enabled = { "true", "false" },
      autosave_interval = { "true", "false" },
      notify = { "true", "false" },
    },
  },
  reload = {
    func = Continuity.reload,
  },
  reset = {
    -- should require bang with unsaved changes?
    func = Continuity.reset,
    kwargs = {
      notify = { "true", "false" },
      reload = { "true", "false" },
    },
  },
  reset_project = {
    func = Continuity.reset_project,
    kwargs = {
      name = Continuity.list_projects,
    },
  },
  save = {
    func = Continuity.save,
    kwargs = {
      attach = { "true", "false" },
      reset = { "true", "false" },
      modified = { "true", "false", "auto" },
      autosave_enabled = { "true", "false" },
      autosave_interval = { "true", "false" },
      notify = { "true", "false" },
    },
  },
  start = {
    func = Continuity.start,
    args = {
      {}, -- This would need path completion, not sure if it's possible to instruct nvim to do this
    },
    kwargs = {
      attach = { "true", "false" },
      reset = { "true", "false", "auto" },
      detach_save = { "true", "false" },
      modified = { "true", "false", "auto" },
      autosave_enabled = { "true", "false" },
      autosave_interval = { "true", "false" },
      notify = { "true", "false" },
    },
  },
  stop = {
    func = Continuity.stop,
  },
}

local function to_lua(val)
  if tonumber(val) then
    return tonumber(val)
  elseif val == "true" then
    return true
  elseif val == "false" then
    return false
  elseif val == "nil" then
    return nil
  end
  return val
end

---@return {args: (string|number|boolean)[], kwargs: table<string, string|number|boolean>}
local function parse_args(args, skip)
  return vim
    .iter(args)
    :skip(skip or 1) -- skip command/subcommand
    :fold({ args = {}, kwargs = {} }, function(acc, v)
      if v:find("=") then
        local param, val = unpack(vim.split(v, "=", { plain = true }))
        acc.kwargs[param] = to_lua(val)
        return acc
      end
      if v ~= "" then
        acc.args[#acc.args + 1] = to_lua(v)
      end
      return acc
    end)
end

---@return string[]
function M.complete(_, line)
  local words = vim.split(line, "%s+", { trimempty = true })
  local current_arg_finished = line:sub(-1) == " "
  local n = #words

  ---@type string[]
  local matches = {}
  if n == 1 then
    matches = vim.tbl_keys(funcs --[[@as table<string,any>]])
  elseif n > 1 then
    local func = funcs[words[2]]
    if not func or not (func.args or func.kwargs) then
      return matches
    end
    local parsed = parse_args(words, 2)
    local required_arg_cnt = vim.iter(func.args or {}):fold(0, function(acc, v)
      return acc + (v.required and 1 or 0)
    end)
    if #vim.tbl_keys(parsed.kwargs) == 0 and #parsed.args < #(func.args or {}) then
      local completion = ((func.args or {})[#parsed.args + 1] or {}).complete or {}
      if type(completion) == "function" then
        matches = vim.list_extend(matches, completion())
      else
        matches = vim.list_extend(matches, completion)
      end
    end
    if
      func.kwargs
      and (
        #parsed.args > required_arg_cnt
        or #parsed.args == required_arg_cnt and current_arg_finished
      )
    then
      local possible_kwargs = vim.tbl_keys(func.kwargs)
      local parsed_kwargs = vim.tbl_keys(parsed.kwargs)
      for _, kwarg in
        ipairs(vim.tbl_filter(function(v)
          return not vim.list_contains(parsed_kwargs, v)
        end, possible_kwargs))
      do
        local completions = func.kwargs[kwarg]
        if type(completions) == "function" then
          completions = completions()
        end
        for _, val in ipairs(completions) do
          matches[#matches + 1] = ("%s=%s"):format(kwarg, val)
        end
      end
    end
  end
  return matches
end

function M.run(params)
  local parsed = parse_args(params.fargs)
  local func = funcs[params.fargs[1]]
  if not func then
    vim.ui.select(M.complete("", "Continuity"), {}, function(item)
      func = funcs[item]
    end)
    if not func then
      return
    end
  end
  local ret
  if func.args then
    ---@type table<integer, boolean|string|number>
    local posargs = parsed.args
    for _ = 1, #func.args - #posargs do
      table.insert(posargs, nil)
    end
    ret = func.func(unpack(parsed.args), func.kwargs and parsed.kwargs)
  else
    ret = func.func(func.kwargs and parsed.kwargs)
  end
  if ret then
    vim.notify(vim.inspect(ret))
  end
end

return M

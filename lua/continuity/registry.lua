local Config = require("continuity.config")
local files = require("resession.files")

local M = {}

---@type ContinuityState?
local data = nil

function M.load()
  -- ensure the table is in the global
  data = files.load_json_file(Config.opts.registry_file) or {}
end

function M.write()
  files.write_json_file(Config.opts.registry_file, data)
end

---@param path string
---@return ContinuityCwdData
function M.get(path)
  if not data then
    M.load()
  end
  ---@cast data ContinuityState
  if not data.registry[path] then
    data.registry[path] = { sessions = {} }
  end
  return data.registry[path]
end

---@param path string
---@param opts table?
---@return ContinuitySession[]
function M.get_sessions(path, opts)
  local cwd_data = M.get(path)
  opts = opts or {}
  return vim.tbl_filter(function(value)
    return not opts.branch or opts.branch == value.branch
  end, cwd_data.sessions)
end

---@param path string
---@param session ContinuitySession
---@param opts table?
function M.write_session(path, session, opts)
  opts = opts or {}
  local existing = vim.tbl_filter(function(value)
    return value.uuid == session.uuid
  end, M.get(path))
  if #existing > 0 then
    return
  end
  table.insert(data.registry[path].sessions, session)
  M.write()
end

return M

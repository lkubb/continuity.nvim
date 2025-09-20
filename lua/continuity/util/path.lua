---@class continuity.util.Path
local M = {}

---@diagnostic disable-next-line: deprecated
local uv = vim.uv or vim.loop

---@type boolean
M.is_windows = uv.os_uname().version:match("Windows")

---@type boolean
M.is_mac = uv.os_uname().sysname == "Darwin"

---@type string
M.sep = M.is_windows and "\\" or "/"

---Normalize a path by making it absolute and ensuring a trailing /
---@param path string The path to normalize
---@return string
function M.norm(path)
  path = vim.fn.fnamemodify(path, ":p")
  path = path:sub(-1) ~= "/" and path .. "/" or path
  return path
end

--- Check if any of a variable number of paths exists
---@param ... string The paths to check
---@return boolean
M.any_exists = function(...)
  for _, name in ipairs({ ... }) do
    if M.exists(name) then
      return true
    end
  end
  return false
end

--- Check if a path exists
---@param filepath string The path to check
---@return boolean
M.exists = function(filepath)
  local stat = uv.fs_stat(filepath)
  return stat ~= nil and stat.type ~= nil
end

--- Join a variable number of path segments into a relative path specific to the OS
---@return string
M.join = function(...)
  return table.concat({ ... }, M.sep)
end

--- Check whether a path is contained in a directory
---@param dir string
---@param path string
---@return boolean
M.is_subpath = function(dir, path)
  return string.sub(path, 0, string.len(dir)) == dir
end

--- Given a path, replace $HOME with ~ if present.
---@param path string The path to shorten
---@return string
M.shorten_path = function(path)
  local home = os.getenv("HOME")
  if not home then
    return path
  end
  local idx, chars = string.find(path, home)
  if idx == 1 then
    ---@cast chars integer
    return "~" .. string.sub(path, idx + chars)
  else
    return path
  end
end

--- Get a path relative to a standard path
---@param stdpath 'cache'|'config'|'data'|'log'|'run'|'state'
---@param ... string Variable number of path segments to append to the stdpath in OS-specific format
M.get_stdpath_filename = function(stdpath, ...)
  local ok, dir = pcall(vim.fn.stdpath, stdpath)
  if not ok then
    if stdpath == "log" then
      return M.get_stdpath_filename("cache", ...)
    elseif stdpath == "state" then
      return M.get_stdpath_filename("data", ...)
    else
      error(dir)
    end
  end
  ---@cast dir string
  return M.join(dir, ...)
end

--- Try to read a file and return its contents on success
---@param filepath string
---@return string?
M.read_file = function(filepath)
  if not M.exists(filepath) then
    return nil
  end
  local fd = assert(uv.fs_open(filepath, "r", 420)) -- 0644
  local stat = assert(uv.fs_fstat(fd))
  local content = uv.fs_read(fd, stat.size)
  uv.fs_close(fd)
  return content
end

---Read a file and return a list of its lines.
---@param file string The path to read. Must exist, otherwise an error is raised.
---@return string[]
function M.read_lines(file)
  local lines = {}
  for line in io.lines(file) do
    lines[#lines + 1] = line
  end
  return lines
end

--- Try to load a file and return its JSON-decoded contents on success
---@param filepath string
---@return any?
M.load_json_file = function(filepath)
  local content = M.read_file(filepath)
  if content then
    return vim.json.decode(content, { luanil = { object = true } })
  end
end

--- Create a directory, including parents
---@param dirname string The path of the directory to create
---@param perms? integer The permissions to use for the final directory. Intermediate ones are created with the default permissions. Defaults to 493 (== 0o755)
M.mkdir = function(dirname, perms)
  if not perms then
    perms = 493 -- 0755
  end
  if not M.exists(dirname) then
    local parent = vim.fn.fnamemodify(dirname, ":h")
    if not M.exists(parent) then
      M.mkdir(parent)
    end
    uv.fs_mkdir(dirname, perms)
  end
end

--- Write a file (synchronously). Currently performs no error checking.
---@param filename string The path of the file to write
---@param contents string The contents to write
M.write_file = function(filename, contents)
  M.mkdir(vim.fn.fnamemodify(filename, ":h"))
  local fd = assert(uv.fs_open(filename, "w", 420)) -- 0644
  uv.fs_write(fd, contents)
  uv.fs_close(fd)
end

--- Ensure a file is absent
---@param filename string
---@return boolean?
M.delete_file = function(filename)
  if M.exists(filename) then
    return (uv.fs_unlink(filename))
  end
end

--- Delete a directory, optionally recursively
---@param dirname string The path of the directory to delete
---@param opts {recursive?: boolean}
M.rmdir = function(dirname, opts)
  if M.exists(dirname) then
    opts = opts or {}
    return vim.fs.rm(dirname, opts)
  end
end

--- Dump a lua variable to a JSON-encoded file (synchronously)
---@param filename string The path of the file to dump to
---@param obj any The data to dump
M.write_json_file = function(filename, obj)
  ---@diagnostic disable-next-line: param-type-mismatch
  M.write_file(filename, vim.json.encode(obj))
end

--- Get the path to the directory that stores session files.
---@param dirname string The name of the session directory
---@return string
M.get_session_dir = function(dirname)
  return M.get_stdpath_filename("data", dirname)
end

--- Get the path to the file that stores a saved session.
---@param name string The name of the session
---@param dirname string The name of the session directory
---@return string
M.get_session_file = function(name, dirname)
  local filename = string.format("%s.json", name:gsub(M.sep, "_"):gsub(":", "_"))
  return M.join(M.get_session_dir(dirname), filename)
end

return M

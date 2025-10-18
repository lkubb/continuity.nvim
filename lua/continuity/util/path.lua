---@class continuity.util.path
local M = {}

---@diagnostic disable-next-line: deprecated
local uv = vim.uv or vim.loop
local tohex = require("bit").tohex

---@type boolean
M.is_windows = uv.os_uname().version:match("Windows")

---@type boolean
M.is_mac = uv.os_uname().sysname == "Darwin"

---@type string
M.sep = M.is_windows and "\\" or "/"

--- Normalize a path by making it absolute and ensuring a trailing /
---@param path string Path to normalize
---@return string normalized_path #
function M.norm(path)
  path = vim.fn.fnamemodify(path, ":p")
  path = path:sub(-1) ~= "/" and path .. "/" or path
  return path
end

--- Check if any of a variable number of paths exists
---@param ... string Paths to check
---@return boolean any_exists #
function M.any_exists(...)
  for _, name in ipairs({ ... }) do
    if M.exists(name) then
      return true
    end
  end
  return false
end

--- Check if a path exists
---@param filepath string Path to check
---@return boolean exists #
function M.exists(filepath)
  local stat = uv.fs_stat(filepath)
  return stat ~= nil and stat.type ~= nil
end

--- Join a variable number of path segments into a relative path specific to the OS
---@param ... string Path segments to join
---@return string joined_path #
function M.join(...)
  return table.concat({ ... }, M.sep)
end

--- Check whether a path is contained in a directory
---@param dir string Root dir to check
---@param path string Path to check
---@return boolean is_subpath #
function M.is_subpath(dir, path)
  return string.sub(path, 0, string.len(dir)) == dir
end

--- Given a path, replace $HOME with ~ if present.
---@param path string Path to shorten
---@return string shortened_path #
function M.shorten_path(path)
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
---@param stdpath "cache"|"config"|"data"|"log"|"run"|"state" Name of the stdpath
---@param ... string Path segments to append to the stdpath in OS-specific format
---@return string
function M.get_stdpath_filename(stdpath, ...)
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

--- Try to read a file and return its contents on success.
--- Does not error, returns nil instead.
---@param filepath string Path to read
---@return string? file_contents #
function M.read_file(filepath)
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
---@param file string Path to read. Must exist, otherwise an error is raised.
---@return string[] file_lines #
function M.read_lines(file)
  local lines = {}
  for line in io.lines(file) do
    lines[#lines + 1] = line
  end
  return lines
end

--- Try to load a file and return its JSON-decoded contents on success
---@param filepath string Path to read
---@return any? loaded_json #
function M.load_json_file(filepath)
  local content = M.read_file(filepath)
  if content then
    return vim.json.decode(content, { luanil = { object = true } })
  end
end

--- Create a directory, including parents
---@param dirname string Path of the directory to create
---@param perms? integer #
---   Permissions to use for the final directory.
---   Intermediate ones are created with the default permissions.
---   Defaults to 493 (== 0o755)
function M.mkdir(dirname, perms)
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

---@generic T
---@param dir string Directory to list
---@param predicate (fun(entry: uv.fs_readdir.entry, dir: string, depth: integer): T?, boolean?)? #
---   Function to map list results to return value.
---   If unspecified, returns a list of file names.
---@param order_by ("filename"|"creation_time"|"modification_time"|fun(a: [string, T], b: [string, T]): boolean)? #
---   Order the returned list in some fashion.
---   If a function is passed, it receives a tuple of [full_path, predicate_return].
---@return T[] mapped_matches #
function M.ls(dir, predicate, order_by)
  predicate = predicate
    or function(entry, _, _)
      return entry.type == "file" and entry.name
    end
  ---@type "filename"|"creation_time"|"modification_time"|fun(a: [string, T], b: [string, T]): boolean
  order_by = order_by or "filename"

  local dirs = { { dir, 0 } } ---@type [string, integer][]
  local visited = {} ---@type table<string, true?>
  local ret = {} ---@type [string, T][]

  local function ls_inner(dir_inner, depth)
    visited[dir_inner] = true
    ---@diagnostic disable-next-line: param-type-mismatch, param-type-not-match, unnecessary-assert
    local fd = assert(uv.fs_opendir(dir_inner, nil, 256))
    ---@diagnostic disable-next-line: cast-type-mismatch
    ---@cast fd uv.luv_dir_t
    local entries = uv.fs_readdir(fd)
    while entries do
      for _, entry in ipairs(entries) do
        local res, recurse = predicate(entry, dir_inner, depth)
        if res then
          ret[#ret + 1] = { M.join(dir_inner, entry.name), res }
        end
        if entry.type == "directory" and recurse then
          local dir_path = M.join(dir_inner, entry.name)
          if not visited[dir_path] then
            dirs[#dirs + 1] = { dir_path, depth + 1 }
          end
        end
      end
      entries = uv.fs_readdir(fd)
    end
    uv.fs_closedir(fd)
  end

  while #dirs > 0 do
    for i, idir in ipairs(dirs) do
      ls_inner(unpack(idir))
      dirs[i] = nil
    end
  end

  -- Order options
  if order_by == "filename" then
    -- Sort by filename
    table.sort(ret, function(a, b)
      return a[1] < b[1]
    end)
  elseif order_by == "modification_time" then
    -- Sort by modification_time
    local default = { mtime = { sec = 0 } }
    table.sort(ret, function(a, b)
      local file_a = uv.fs_stat(a[1]) or default
      local file_b = uv.fs_stat(b[1]) or default
      return file_a.mtime.sec > file_b.mtime.sec
    end)
  elseif order_by == "creation_time" then
    -- Sort by creation_time in descending order (most recent first)
    local default = { birthtime = { sec = 0 } }
    table.sort(ret, function(a, b)
      local file_a = uv.fs_stat(a[1]) or default
      local file_b = uv.fs_stat(b[1]) or default
      return file_a.birthtime.sec > file_b.birthtime.sec
    end)
  elseif type(order_by) == "function" then
    table.sort(ret, order_by)
  end
  return vim
    .iter(ret)
    :map(function(v)
      return v[2]
    end)
    :totable()
end

--- Write a file (synchronously). Currently performs no error checking.
---@param filename string Path of the file to write
---@param contents string Contents to write
function M.write_file(filename, contents)
  M.mkdir(vim.fn.fnamemodify(filename, ":h"))
  local fd = assert(uv.fs_open(filename, "w", 420)) -- 0644
  uv.fs_write(fd, contents)
  uv.fs_close(fd)
end

--- Ensure a file is absent
---@param filename string Path of the file to ensure is absent
---@return boolean? existed_and_deleted #
function M.delete_file(filename)
  if M.exists(filename) then
    return (uv.fs_unlink(filename))
  end
end

--- Delete a directory, optionally recursively
---@param dirname string Path of the directory to delete
---@param opts {recursive?: boolean} Optionally delete recursively
function M.rmdir(dirname, opts)
  if M.exists(dirname) then
    opts = opts or {}
    vim.fs.rm(dirname, opts)
    return true
  end
end

--- Dump a lua variable to a JSON-encoded file (synchronously)
---@param filename string Path of the file to dump to
---@param obj any Data to dump
function M.write_json_file(filename, obj)
  ---@diagnostic disable-next-line: param-type-mismatch
  M.write_file(filename, vim.json.encode(obj))
end

--- Get the path to the directory that stores session files.
---@param dirname string Name of the session directory
---@return string absolute_session_dir #
function M.get_session_dir(dirname)
  return M.get_stdpath_filename("data", dirname)
end

--- Get the path to the file that stores a saved session.
---@param name string Name of the session
---@param dirname string Name of the session directory
---@return string session_file #
function M.get_session_file(name, dirname)
  local filename = string.format("%s.json", M.escape(name))
  return M.join(M.get_session_dir(dirname), filename)
end

--- Get the path to the directory that holds session-associated files
--- like modified buffer contents and corresponding undo history.
---@param name string Name of the session
---@param dirname string Name of the session directory
---@return string state_dir #
function M.get_session_state_dir(name, dirname)
  return M.join(M.get_session_dir(dirname), M.escape(name))
end

--- Get both session-related paths (session data filename and state directory) in one swoop.
---@param name string Name of the session
---@param dirname string Name of the session directory
---@return string session_file #
---@return string state_dir #
---@return string context_dir #
function M.get_session_paths(name, dirname)
  local session_name = M.escape(name)
  local session_dir = M.get_session_dir(dirname)
  local filename = string.format("%s.json", session_name)
  return M.join(session_dir, filename),
    M.join(session_dir, session_name),
    M.join(session_dir, "__state")
end

--- Get the path to the file that stores a saved autosession.
---@param name string Name of the session
---@param dir string Absolute path of the directory to save sessions in
---@return string session_file #
function M.get_autosession_file(name, dir)
  local filename = string.format("%s.json", M.escape(name))
  return M.join(dir, filename)
end

--- Get the path to the project sessions dir
---@param project_name string Name of the project
---@param dir string Absolute path of the directory to save projects in
---@return string project_dir #
function M.get_autosession_project_dir(project_name, dir)
  return M.join(M.get_session_dir(dir), M.escape(project_name))
end

--- Get all session-related paths (session data filename, state directory and project state dir) in one swoop.
---@param name string Name of the session
---@param dir string Absolute path of the directory to save sessions in
---@return string session_file #
---@return string state_dir #
---@return string context_dir #
function M.get_autosession_paths(name, dir)
  local session_name = M.escape(name)
  local filename = string.format("%s.json", session_name)
  return M.join(dir, filename), M.join(dir, session_name), M.join(dir, "__state")
end

---@param char string Single-byte (!) single character to turn into its hexadecimal representation
---@return string percent_hex #
---   %XX-encoded representation of `char`
local function char_to_percent(char)
  return "%" .. tohex(char:byte(), 2):upper()
end

-- By default, escape / (Unix pathsep), all characters forbidden on Windows,
-- the `%` itself (necessary for the encoding to be reversible), all control characters
-- to avoid filename display issues, the tilde to not make the impression of
-- being a special/backup file and somewhat arbitrarily the backtick, single quote,
-- whitespace and plus sign as well as all control characters.
local escape_chars = [[/\|<>:*?"%%~`' +%c]]

--- Escape select characters in a string by percent-encoding their hex value.
--- If the first character is a dot, always encodes it to avoid creating hidden files.
--- Important: Only supports single-byte characters for substitution. Does not normalize CR/LF.
---@param str string String to escape
---@param chrs? string Inner content of a Lua character group. Matches are escaped by percent-encoding them. Defaults to ``/\|<>:*?"%%'` +~%c``.
---@return string escaped #
function M.escape(str, chrs)
  local first = ""
  if str:sub(1, 1) == "." then
    first = "%2E"
    str = str:sub(2)
  end
  return first .. (str:gsub("([" .. (chrs or escape_chars) .. "])", char_to_percent))
end

---@param hex string Byte in hexadecimal notation to turn into a raw character
---@return string char #
local function hex_to_char(hex)
  return string.char((assert(tonumber(hex, 16), ("Failed decoding hex value of '%s'"):format(hex))))
end

--- Decode a `%XX`-encoded string into its original form.
---@param str string Encoded string
---@return string raw #
function M.unescape(str)
  return (str:gsub("%%([A-F0-9][A-F0-9])", hex_to_char))
end

return M

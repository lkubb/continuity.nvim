---@class continuity.util.shada
local M = {}

---@namespace continuity.util.shada

--- (Numeric) entry types `1` through `11`, specifies entry kind in ShaDa format.
---@enum EntryType
local ENTRY_TYPE = {
  header = 1,
  search_pattern = 2,
  sub_string = 3,
  history = 4,
  register = 5,
  variable = 6,
  global_mark = 7,
  jump = 8,
  buffer_list = 9,
  local_mark = 10,
  change = 11,
}

--- Internal aliases for ShaDa entry types `1` through `11`
--- (`header`|`search_pattern`|`sub_string`|`history`|`register`|`variable`|`global_mark`|`jump`|`buffer_list`|`local_mark`|`change`).
---@enum EntryName
local ENTRY_TYPE_rev = {
  [1] = "header",
  [2] = "search_pattern",
  [3] = "sub_string",
  [4] = "history",
  [5] = "register",
  [6] = "variable",
  [7] = "global_mark",
  [8] = "jump",
  [9] = "buffer_list",
  [10] = "local_mark",
  [11] = "change",
}

--- (Numeric) register type indicators `0` through `2`
--- (charwise/linewise/blockwise).
---@enum RegType
local REG_TYPE = {
  char = 0,
  line = 1,
  block = 2,
}

--- Internal aliases for register type indicators `0` through `2`
--- (`char`|`line`|`block`).
---@enum RegTypeName
local _REG_TYPE_rev = {
  [0] = "char",
  [1] = "line",
  [2] = "block",
}

--- (Numeric) history line type indicators `0` through `4`
--- (command/search/expression/input/debug).
---@enum HistType
local HIST_TYPE = {
  cmd = 0,
  search = 1,
  expr = 2,
  input = 3,
  debug = 4,
}

--- Internal aliases for history line type indicators `0` through `4`
--- (`cmd`|`search`|`expr`|`input`|`debug`).
---@enum HistName
local HIST_TYPE_rev = {
  [0] = "cmd",
  [1] = "search",
  [2] = "expr",
  [3] = "input",
  [4] = "debug",
}

--- Get an item or list of items of a `*Type`/`*Name` enum and return
--- a list that contains all **raw** referenced values (`*Type`), for filtering purposes.
---@generic K, V
---@param base table<K, V>
---@param val K|V|(K|V)[]
---@return V[]
local function ensure_raw_list(base, val)
  if type(val) ~= "table" then
    val = { val }
  end
  return vim
    .iter(val)
    :map(function(v)
      return base[v] or v
    end)
    :totable()
end

--- Represents a complete file in ShaDa format.
--- Allows to create/mutate/inspect/filter/write/apply ShaDa from Lua.
---@class Shada
---@field entries (integer|table)[] #
---   Raw, list-like data structure of ShaDa entries, not split into entries
local Shada = {}

--- Add any ShaDa entry.
---@overload fun(typ: "header", data: EntryData.Header, timestamp?: integer): self
---@overload fun(typ: "search_pattern", data: EntryData.SearchPattern, timestamp?: integer): self
---@overload fun(typ: "sub_string", data: EntryData.SubString, timestamp?: integer): self
---@overload fun(typ: "history", data: EntryData.History, timestamp?: integer): self
---@overload fun(typ: "register", data: EntryData.Register, timestamp?: integer): self
---@overload fun(typ: "variable", data: EntryData.Variable, timestamp?: integer): self
---@overload fun(typ: "global_mark", data: EntryData.GlobalMark, timestamp?: integer): self
---@overload fun(typ: "jump", data: EntryData.Jump, timestamp?: integer): self
---@overload fun(typ: "buffer_list", data: EntryData.BufferList, timestamp?: integer): self
---@overload fun(typ: "local_mark", data: EntryData.LocalMark, timestamp?: integer): self
---@overload fun(typ: "change", data: EntryData.Change, timestamp?: integer): self
---@param typ EntryType|EntryName #
---   Alias of entry kind (`header`, `search_pattern`, `sub_string`,
---   `history`, `register`, `variable`, `global_mark`, `jump`,
---   `buffer_list`, `local_mark`, `change`)
---   or numeric identifier.
---@param data EntryData Entry kind-specific data table
---@param timestamp? integer Timestamp of entry, defaults to now
---@return self self #
function Shada:add(typ, data, timestamp)
  local data_packed = vim.fn.msgpackdump({ data }, "B")
  local packed_len = #data_packed
  vim.list_extend(
    self.entries,
    { ENTRY_TYPE[typ] or typ, timestamp or os.time(), packed_len, data }
  )
  return self
end

--- Add a search/substitution pattern entry.
--- Note: Support is very limited here, use `:add` for arbitrary data.
--- Usually one for both `is_substitution` permutations. One entry should have `last_used`.
---@param pattern string Search pattern
---@param last_used? boolean Whether this pattern was the most recently used one
---@param is_substitution? boolean Whether this pattern is a substitution
---@param backwards? boolean Whether the pattern was executed in backwards direction (via `?` instead of `/`)
---@param timestamp? integer Timestamp of entry, defaults to now
---@return self self #
function Shada:add_search(pattern, last_used, is_substitution, backwards, timestamp)
  ---@type EntryData.SearchPattern
  local data = { sp = pattern, su = last_used, ss = is_substitution, sb = backwards }
  return self:add("search_pattern", data, timestamp)
end

--- Add a `:s[ubstitution]` replacement string entry. Usually only one per ShaDa file (last one).
---@param contents string Substitution replacement string
---@param timestamp? integer Timestamp of entry, defaults to now
---@return self self #
function Shada:add_sub(contents, timestamp)
  ---@type EntryData.SubString
  local data = { contents }
  return self:add("sub_string", data, timestamp)
end

--- Add a history entry.
---@overload fun(typ: "search", contents: string, sep: string): self
---@param typ HistName|HistType #
---   Alias of history kind (`cmd`, `search`, `expr`, `input`, `debug`)
---   or numeric identifier
---@param contents string History entry contents
---@param sep? string Single-char separator. Required when typ == search, e.g. `/`
---@param timestamp? integer Timestamp of entry, defaults to now
---@return self self #
function Shada:add_hist(typ, contents, sep, timestamp)
  ---@type EntryData.History
  local data = {
    HIST_TYPE[typ] or typ,
    contents,
    typ == "search"
        and assert(sep and sep:len() == 1 and sep, "Search requires single-char sep"):byte()
      or nil,
  }
  return self:add("history", data, timestamp)
end

--- Add a register entry.
---@overload fun(name: string, contents: string[], typ: nil): self
---@overload fun(name: string, contents: string[], typ: "char"): self
---@overload fun(name: string, contents: string[], typ: "line"): self
---@overload fun(name: string, contents: string[], typ: "block", width: integer): self
---@overload fun(name: string, contents: string[], typ: nil, width: nil, timestamp: integer): self
---@overload fun(name: string, contents: string[], typ: "char", width: nil, timestamp: integer): self
---@overload fun(name: string, contents: string[], typ: "line", width: nil, timestamp: integer): self
---@overload fun(name: string, contents: string[], typ: "block", width: integer, timestamp: integer): self
---@param name string Single-char register name.
---@param contents string[] Array of register content lines
---@param typ? RegTypeName|RegType #
---   Alias of register type (`char`, `line`, `block`)
---   or numeric identifier. Defaults to `char`.
---@param unnamed? boolean Unnamed register points to this one.
---@param width? integer Width of block type. Only when `typ` is `block`.
---@param timestamp? integer Timestamp of entry, defaults to now
---@return self self #
function Shada:add_reg(contents, name, typ, unnamed, width, timestamp)
  typ = typ or "char"
  ---@type EntryData.Register
  local data = {
    rc = contents,
    n = name:byte(),
    rt = REG_TYPE[typ] or typ,
    ru = unnamed,
    rw = width,
  }
  return self:add("register", data, timestamp)
end

--- Add a global variable entry.
---@param name string Global variable name
---@param contents any Object compatible with `msgpackdump()`/`msgpackparse()`
---@param timestamp? integer Timestamp of entry, defaults to now
---@return self self #
function Shada:add_var(name, contents, timestamp)
  local data = { name, contents } ---@type EntryData.Variable
  return self:add("variable", data, timestamp)
end

--- Add a global mark entry.
---@param name string Single-char name of mark
---@param file string - "" Absolute path of the file the global mark points to
---@param line? integer Line number. Defaults to 1.
---@param col? integer Column number. Defaults to 0.
---@param timestamp? integer Timestamp of entry, defaults to now
---@return self self #
function Shada:add_gmark(name, file, line, col, timestamp)
  ---@type EntryData.GlobalMark
  local data = { n = name:upper():byte(), f = file, l = line, c = col }
  return self:add("global_mark", data, timestamp)
end

--- Add a jumplist entry.
---@param file string - "" Absolute path of the file the jumplist entry points to. Must not be the empty string.
---@param line? integer Line number. Defaults to 1.
---@param col? integer Column number. Defaults to 0.
---@param timestamp? integer Timestamp of entry, defaults to now
---@return self self #
function Shada:add_jump(file, line, col, timestamp)
  ---@type EntryData.Jump
  local data = { f = file, l = line, c = col }
  return self:add("jump", data, timestamp)
end

--- Add a buffer-specific local mark entry.
---@param name string Single-char name of mark
---@param file string - "" Absolute path of the file the mark applies to
---@param line? integer Line number. Defaults to 1.
---@param col? integer Column number. Defaults to 0.
---@param timestamp? integer Timestamp of entry, defaults to now
---@return self self #
function Shada:add_lmark(name, file, line, col, timestamp)
  ---@type EntryData.LocalMark
  local data = { n = name:lower():byte(), f = file, l = line, c = col }
  return self:add("global_mark", data, timestamp)
end

--- Add a changelist entry.
---@param file string - "" Absolute path of the file the changelist entry points to
---@param line? integer Line number. Defaults to 1.
---@param col? integer Column number. Defaults to 0.
---@param timestamp? integer Timestamp of entry, defaults to now
---@return self self #
function Shada:add_change(file, line, col, timestamp)
  ---@type EntryData.Change
  local data = { f = file, l = line, c = col }
  return self:add("change", data, timestamp)
end

--- Return a `vim.iter` iterator over the contained ShaDa entries.
---@return Iter shada_iter #
function Shada:iter()
  local i = 0
  local n = #self.entries
  ---@type fun(): Entry?
  local it = function()
    i = i + 4
    if i <= n then
      return { self.entries[i - 3], self.entries[i - 2], self.entries[i - 1], self.entries[i] }
    end
  end
  return vim.iter(it)
end

--- Iterate over contained entries of specific types, including history type selection.
---@param typ EntryType|EntryName|(EntryType|EntryName)[] #
---   Entry type(s) to include.
---   String alias (`history`) or raw type (1-11).
---@param hist_typ? HistType|HistName|(HistType|HistName)[] #
---   History entry type(s) to include, optional.
---   String alias (`cmd`) or raw type (0-4).
---   If unspecified, no additional filtering is performed.
---@return Iter filtered_entries #
---   An iterator over entries of the type(s) specified in `typ`/`hist_typ`
function Shada:filter(typ, hist_typ)
  ---@type EntryType[]
  local raw_typs = ensure_raw_list(ENTRY_TYPE, typ)
  local it = self:iter():filter(function(v)
    ---@cast v Entry
    return vim.list_contains(raw_typs, v[1])
  end)
  if not hist_typ or not vim.list_contains(raw_typs, ENTRY_TYPE.history) then
    return it
  end
  ---@type HistType[]
  local raw_hist_typs = ensure_raw_list(HIST_TYPE, hist_typ)
  return it:filter(function(v)
    if v[1] ~= ENTRY_TYPE.history then
      return true
    end
    ---@cast v Entry.History
    return vim.list_contains(raw_hist_typs, v[4][1])
  end)
end

--- Reduce contained ShaDa entries to specified types.
---@param typ EntryType|EntryName|(EntryType|EntryName)[] #
---   Entry type(s) to include.
---   String alias (`history`) or raw type (1-11).
---@param hist_typ? HistType|HistName|(HistType|HistName)[] #
---   History entry type(s) to include.
---   String alias (`cmd`) or raw type (0-4).
---   If unspecified, no additional filtering is performed.
---@return self shallow_copy_shada #
---   A shallow copy of this ShaDa with only the specified entry types
function Shada:select(typ, hist_typ)
  return Shada.new(vim.iter(self:filter(typ, hist_typ):totable()):flatten(1):totable())
end

--- Return information about the first header entry
---@return {time: integer, [any]: unknown}? rendered_header #
function Shada:header()
  for header in self:filter(ENTRY_TYPE.header) do
    ---@cast header Entry.Header
    ---@diagnostic disable-next-line: return-type-mismatch
    return vim.tbl_extend("error", { time = header[1] }, header[4])
  end
end

--- Get a representative mapping of all contained marks
---@return {[string]: {time: integer, line: integer, col: integer, file: string}?} rendered_marks #
function Shada:marks()
  return self:filter({ ENTRY_TYPE.global_mark, ENTRY_TYPE.local_mark }):fold({}, function(acc, mark)
    ---@cast mark Entry.GlobalMark|Entry.LocalMark
    acc[string.char(mark[4].n or 34)] =
      { time = mark[2], line = mark[4].l or 1, col = mark[4].c or 0, file = mark[4].f }
    return acc
  end)
end

--- Get a representative mapping of all contained registers
---@return {[string]: {time: integer, contents: string[], type: RegTypeName, unnamed: boolean?, width: integer?}?} rendered_registers #
function Shada:registers()
  return self:filter(ENTRY_TYPE.register):fold({}, function(acc, reg)
    ---@cast reg Entry.Register
    acc[string.char(reg[4].n)] = {
      time = reg[2],
      contents = reg[4].rc,
      type = _REG_TYPE_rev[reg[4].rt or 0],
      unnamed = reg[4].ru,
      width = reg[4].rt == REG_TYPE.block and reg[4].rw or nil,
    }
    return acc
  end)
end

--- Write the contents of this builder to a file on disk.
---@param dst? string Path to write to. If unset, generates a temporary file path.
---@return string dst_path Path the ShaDa file was written to
function Shada:write(dst)
  dst = dst or vim.fn.tempname()
  local shada = vim.fn.msgpackdump(self.entries, "B")
  require("continuity.util").path.write_file(dst, shada)
  return dst
end

--- Apply the contained ShaDa on the fly.
---@param opts? ReadOpts
function Shada:read(opts)
  local temp = self:write()
  vim.cmd.rshada({ vim.fn.fnameescape(temp), bang = (opts or {}).bang })
  vim.defer_fn(function()
    require("continuity.util.path").delete_file(temp)
  end, 5000)
end

--- List all included entry types (as their aliases, not numeric).
---@return EntryName[] contained_types #
function Shada:types()
  local res = {} ---@type table<EntryType,true?>
  for entry in self:iter() do
    res[entry[1]] = true
  end
  return vim
    .iter(pairs(res))
    :map(function(t)
      return ENTRY_TYPE_rev[t]
    end)
    :totable()
end

--- List all included history entry types (as their aliases, not numeric).
---@return HistName[] contained_hist_types #
function Shada:hist_types()
  local res = {} ---@type table<HistType,true?>
  for entry in self:filter(ENTRY_TYPE.history) do
    ---@cast entry Entry.History
    res[entry[4][1]] = true
  end
  return vim
    .iter(pairs(res))
    :map(function(t)
      return HIST_TYPE_rev[t]
    end)
    :totable()
end

--- Create a new ShaDa object.
--- @param init? (integer|table)[] Initial ShaDa, e.g. loaded from disk
--- @return Shada shada #
function Shada.new(init)
  return setmetatable({ entries = init or {} }, { __index = Shada })
end

--- Create a new ShaDa builder. `:add` entries and `:write` it to a (temp) path.
---@return Shada shada #
function M.new()
  return Shada.new():add("header", {
    -- The header does not have any functional purpose, just for debugging
    encoding = "utf-8",
    generator = "continuity", -- "nvim"
    version = "0.1.0", -- (tostring(vim.version()):gsub("%+.*$", "")),
    -- max_kbyte = 10,
    -- pid = vim.fn.getpid(),
  })
end

--- Create a new ShaDa builder by initializing its contents from an existing ShaDa file on disk.
--- @param path? string #
---    Path of the ShaDa file to load.
---    Defaults to `'shadafile'` option or `$XDG_STATE_HOME/$NVIM_APPNAME/shada/main.shada`.
---    Note: **Must** exist, otherwise errors.
--- @return Shada loaded_shada #
---    A builder containing the on-disk data. Can be transformed.
function M.from_file(path)
  local pathutil = require("continuity.util.path")
  path = vim.fn.fnamemodify(
    path
      or vim.go.shadafile ~= "" and vim.go.shadafile
      or pathutil.get_stdpath_filename("state", "shada", "main.shada"),
    ":p"
  )
  local contents = require("continuity.util.path").read_file(path)
  if not contents then
    error(("Path '%s' does not exist"):format(path))
  end
  return Shada.new(vim.fn.msgpackparse(contents))
end

return M

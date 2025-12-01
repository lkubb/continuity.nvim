---@meta
---@namespace finni.util.shada

--- Influence `Shada:read` behavior
---@class ReadOpts
---@field bang? boolean #
---   Overwrite this instance's ShaDa-sourced data with
---   the contents in this builder (instead of merging).
---   Defaults to false.

--- Many ShaDa entries are marks. This is the basic type without reference to a file path.
---@class EntryData.BaseMark
---@field f string - "" file name
---@field l? integer line count, defaults to 1
---@field c? integer column count, defaults to 0

---@alias EntryType.Header 1
---@class EntryData.Header
---@field encoding string Usually `utf-8`
---@field generator string Usually `nvim`
---@field max_kbyte integer
---@field pid integer
---@field version string

---@alias EntryType.SearchPattern 2
---@class EntryData.SearchPattern
---@field sp string Search pattern contents.
---@field sm? boolean Effective `'magic'` value. Defaults to true.
---@field sc? boolean Effective `'smartcase'` value. Defaults to false.
---@field sl? boolean Search pattern comes with line offset. Defaults to true. See `'search-offset'`.
---@field se? boolean Search offset requested to place cursor at the end of the pattern. Defaults to false.
---@field so? integer Search offset value. Defaults to 0.
---@field su? boolean This entry was the last used search pattern. Defaults to false.
---@field ss? boolean This entry describes a `:s[ubstitute]` pattern. Defaults to false.
---@field sh? boolean State of `v:hlsearch`.
---@field sb? boolean Search backwards. Defaults to false.

---@alias EntryType.SubString 3
---@class EntryData.SubString
---@field [1] string Last `:s[ubstitute]` replacement string.

---@alias EntryType.History 4
---@class EntryData.History
---@field [1] 0|1|2|3|4 History type (cmd/search/expr/input/debug)
---@field [2] string History line.
---@field [3]? integer #
---   Single byte value of separator char. Only for search type. E.g. `47` (ascii byte of /) for / search entry

---@alias EntryType.Register 5
---@class EntryData.Register
---@field rc string[] Register contents (array of lines)
---@field n integer Single byte value of the register name (i.e. ASCII char, e.g. 48 for "0).
---@field rt? 0|1|2 Register type (char/line/blockwise), defaults to `0` (charwise).
---@field ru? boolean Unnamed register pointed here
---@field rw? integer Register width. Only for block type.

---@alias EntryType.Variable 6
---@class EntryData.Variable
---@field [1] string Name of the variable
---@field [2] any Any object compatible with `msgpackdump()`/`msgpackparse()`

---@alias EntryType.GlobalMark 7
---@class EntryData.GlobalMark: EntryData.BaseMark
---@field n integer #
---   Single byte value of the mark name (ASCII char, uppercase). In theory defaults to 34 (= `"`, unnamed register).

---@alias EntryType.Jump 8
---@class EntryData.Jump: EntryData.BaseMark

---@alias EntryType.BufferList 9
---@class EntryData.BufferList.Item: EntryData.BaseMark
---@alias EntryData.BufferList EntryData.BufferList.Item[]

---@alias EntryType.LocalMark 10
---@class EntryData.LocalMark: EntryData.BaseMark
---@field n integer #
---   Single byte value of the mark name (ASCII char, lowercase). In theory defaults to 34 (= `"`, unnamed register).

---@alias EntryType.Change 11
---@class EntryData.Change: EntryData.BaseMark

---@alias EntryField.Timestamp integer UNIX timestamp of entry birth
---@alias EntryField.ByteLen integer Byte length of embedded entry kind-specific data (msgpack-encoded)

--- Generic ShaDa entry. Used for building concrete types.
---@alias ShadaEntry<RawType: EntryType, DataType: table> [RawType, EntryField.Timestamp, EntryField.ByteLen, DataType]

--- Header entry. Of no functional value, just for debugging.
---@alias Entry.Header ShadaEntry<1, EntryData.Header>
--- Recent search pattern. Usually 2 per ShaDa, (1) `ss` = `true` (2) `ss` = `false`.
--- One of the entries should have `su` == `true`.
---@alias Entry.SearchPattern ShadaEntry<2, EntryData.SearchPattern>
--- Last `:s[ubstitute]` replacement string
---@alias Entry.SubString ShadaEntry<3, EntryData.SubString>
--- One line of (`cmd`|`search`|`expr`|`input`|`debug`) history
---@alias Entry.History ShadaEntry<4, EntryData.History>
--- Named register.
---@alias Entry.Register ShadaEntry<5, EntryData.Register>
--- Global (`UPPERCASE_ONLY` but not `_WITHOUT_LEADING_UPPERCASE`) variable.
---@alias Entry.Variable ShadaEntry<6, EntryData.Variable>
--- Global (uppercase) mark, including `'0-'9`.
---@alias Entry.GlobalMark ShadaEntry<7, EntryData.GlobalMark>
--- Jumplist item of last active window (named file buffers only).
---@alias Entry.Jump ShadaEntry<8, EntryData.Jump>
--- List of loaded buffers and recent cursor positions.
---@alias Entry.BufferList ShadaEntry<9, EntryData.BufferList>
--- Buffer-local (lowercase) mark of some recently active buffer.
---@alias Entry.LocalMark ShadaEntry<10, EntryData.LocalMark>
--- Changelist item of some recently active named file buffer.
---@alias Entry.Change ShadaEntry<11, EntryData.Change>

--- Union of all concrete entry types found in the ShaDa format
---@alias Entry Entry.Header|Entry.SearchPattern|Entry.SubString|Entry.History|Entry.Register|Entry.Variable|Entry.GlobalMark|Entry.Jump|Entry.BufferList|Entry.LocalMark|Entry.Change A complete, serialized ShaDa entry.

--- Union of all concrete entry type data formats found in the ShaDa format
---@alias EntryData EntryData.Header|EntryData.SearchPattern|EntryData.SubString|EntryData.History|EntryData.Register|EntryData.Variable|EntryData.GlobalMark|EntryData.Jump|EntryData.BufferList|EntryData.LocalMark|EntryData.Change ShaDa entry kind-specific data. Note: Unknown fields are ignored by nvim.

--@alias EntryType EntryType.Header|EntryType.SearchPattern|EntryType.SubString|EntryType.History|EntryType.Register|EntryType.Variable|EntryType.GlobalMark|EntryType.Jump|EntryType.BufferList|EntryType.LocalMark|EntryType.Change
--@alias EntryName ("header"|"search_pattern"|"sub_string"|"history"|"register"|"variable"|"global_mark"|"jump"|"buffer_list"|"local_mark"|"change")

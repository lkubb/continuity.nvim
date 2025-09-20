local M = {}

---@type boolean?
local seeded
local uuid_v4_template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"

--- Generate a UUID for a buffer.
--- They are used to keep track of unnamed buffers between sessions
--- and as a general identifier when preserving unwritten changes.
---@return continuity.BufUUID
M.generate_uuid = function()
  if not seeded then
    math.randomseed(os.time())
    ---@diagnostic disable-next-line: unused
    seeded = true
  end
  local uuid = string.gsub(uuid_v4_template, "[xy]", function(c)
    local r = math.random()
    local v = c == "x" and math.floor(r * 0x10) or (math.floor(r * 0x4) + 8)
    return string.format("%x", v)
  end)
  return uuid
end

--- List all untitled buffers using bufnr and uuid.
---@return {buf: continuity.BufNr, uuid: continuity.BufUUID?}[]
local function list_untitled_buffers()
  local res = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf) == "" then
      table.insert(res, { buf = buf, uuid = vim.b[buf].continuity_uuid })
    end
  end
  return res
end

--- Ensure a specific buffer exists (represented by file path or UUID) and has any UUID.
--- File path: Ensure the file is loaded into a buffer and has any UUID. If it does not, assign it the specified one.
--- Unnamed: Ensure an unnamed buffer with the specified UUID exists. If not, create a new unnamed buffer and assign the specified UUID.
---@param name string The path of the buffer or the empty string ("") for unnamed buffers.
---@param uuid? continuity.BufUUID The UUID the buffer should have.
---@return integer The buffer ID of the specified buffer.
M.managed = function(name, uuid)
  local bufnr
  if name ~= "" then
    bufnr = vim.fn.bufadd(name)
  else
    for _, buf in ipairs(list_untitled_buffers()) do
      if buf.uuid == uuid then
        bufnr = buf.buf
        break
      end
    end
    if not bufnr then
      bufnr = vim.fn.bufadd("")
    end
  end
  vim.b[bufnr].continuity_uuid = vim.b[bufnr].continuity_uuid or uuid or M.generate_uuid()
  return bufnr
end

---List all continuity-managed buffers.
---@return continuity.ManagedBufID[]
function M.list()
  local res = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.b[buf].continuity_uuid then
      table.insert(res, {
        buf = buf,
        name = vim.api.nvim_buf_get_name(buf),
        uuid = vim.b[buf].continuity_uuid,
      })
    end
  end
  return res
end

---List all continuity-managed buffers that were modified.
---@return continuity.ManagedBufID[]
function M.list_modified()
  local res = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    -- Only list buffers that are known to us. This funtion is called during save,
    -- a missing uuid means the buffer should not be saved at all
    if
      vim.b[buf].continuity_uuid
      and (vim.b[buf]._continuity_needs_restore or vim.bo[buf].modified)
    then
      local in_win = vim.fn.bufwinid(buf)
      table.insert(res, {
        buf = buf,
        name = vim.api.nvim_buf_get_name(buf),
        uuid = vim.b[buf].continuity_uuid,
        in_win = in_win > 0 and in_win or false,
      })
    end
  end
  return res
end

return M

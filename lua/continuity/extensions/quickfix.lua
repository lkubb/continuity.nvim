---@type continuity.core.Extension
local M = {}

---@return [continuity.core.Snapshot.QFList[]?, integer?]
M.on_save = function(_, buflist)
  local cnt = vim.fn.getqflist({ nr = "$" }).nr
  ---@type continuity.core.Snapshot.QFList[]
  local ret = {}
  if cnt <= 0 then
    ---@diagnostic disable-next-line: return-type-mismatch
    return ret
  end
  local pos = vim.fn.getqflist({ nr = 0 }).nr ---@type integer
  for i = 1, cnt do
    local qflist = vim.fn.getqflist({ nr = i, all = true })
    ret[#ret + 1] = {
      idx = qflist.idx,
      title = qflist.title,
      context = qflist.context ~= "" and qflist.context or nil,
      efm = qflist.efm,
      quickfixtextfunc = qflist.quickfixtextfunc ~= "" and qflist.quickfixtextfunc or nil,
      items = vim.tbl_map(function(item)
        return {
          filename = item.bufnr and buflist:add(vim.api.nvim_buf_get_name(item.bufnr)),
          module = item.module ~= "" and item.module or nil,
          lnum = item.lnum,
          end_lnum = item.end_lnum ~= 0 and item.end_lnum or nil,
          col = item.col ~= 1 and item.col or nil,
          end_col = item.end_col ~= 0 and item.end_col or nil,
          vcol = item.vcol ~= 0 and item.vcol or nil,
          nr = item.nr ~= 0 and item.nr or nil,
          pattern = item.pattern ~= "" and item.pattern or nil,
          text = item.text,
          type = item.type ~= "" and item.type or nil,
          valid = item.valid ~= 1 and item.valid or nil,
        }
      end, qflist.items),
    }
  end
  return { ret, pos }
end

---@param data [continuity.core.Snapshot.QFList[]?, integer?]
---@param buflist string[]
M.on_pre_load = function(data, _, buflist)
  local lists, pos = data[1], data[2]
  if not lists then
    return
  ---@diagnostic disable-next-line: undefined-field
  elseif lists.lnum then
    ---@diagnostic disable-next-line: assign-type-mismatch, missing-fields
    -- migration
    lists, pos = { { items = data } }, 1
  end
  vim.fn.setqflist({}, "f") -- ensure lists are always cleared
  vim.iter(lists):each(function(qflist)
    qflist.context = qflist.context or ""
    qflist.quicktextfunc = qflist.quicktextfunc or ""
    qflist.items = vim
      .iter(qflist.items or {})
      :map(function(item)
        if item.filename then
          item.filename = buflist[item.filename] or item.filename
        end
        return vim.tbl_extend("keep", item, {
          module = "",
          end_lnum = 0,
          col = 1,
          end_col = 0,
          vcol = 0,
          nr = 0,
          pattern = "",
          type = "",
          valid = 1,
        })
      end)
      :totable()
    vim.fn.setqflist({}, " ", qflist)
  end)
  vim.cmd.chistory({ count = pos, mods = { silent = true } })
end

---@diagnostic disable-next-line: unused
M.is_win_supported = function(winid, bufnr)
  if vim.bo[bufnr].buftype ~= "quickfix" then
    return false
  end
  local wininfo = vim.fn.getwininfo(winid)[1] or {}
  return wininfo.quickfix == 1 and wininfo.loclist == 0
end

---@diagnostic disable-next-line: unused
M.save_win = function(winid)
  return {}
end

---@diagnostic disable-next-line: unused
M.load_win = function(winid, config)
  vim.api.nvim_set_current_win(winid)
  vim.cmd("vertical copen")
  vim.api.nvim_win_close(winid, true)
  return vim.api.nvim_get_current_win()
end

return M

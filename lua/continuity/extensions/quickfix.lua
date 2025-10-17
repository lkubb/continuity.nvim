---@type continuity.core.Extension
local M = {}

M.on_save = function()
  local cnt = vim.fn.getqflist({ nr = "$" }).nr
  local ret = {}
  if cnt <= 0 then
    return ret
  end
  local pos = vim.fn.getqflist({ nr = 0 }).nr
  for i = 1, cnt do
    local qflist = vim.fn.getqflist({ nr = i, all = true })
    ret[#ret + 1] = {
      idx = qflist.idx,
      title = qflist.title,
      efm = qflist.efm,
      quickfixtextfunc = qflist.quickfixtextfunc,
      items = vim.tbl_map(function(item)
        return {
          filename = item.bufnr and vim.api.nvim_buf_get_name(item.bufnr),
          module = item.module,
          lnum = item.lnum,
          end_lnum = item.end_lnum,
          col = item.col,
          end_col = item.end_col,
          vcol = item.vcol,
          nr = item.nr,
          pattern = item.pattern,
          text = item.text,
          type = item.type,
          valid = item.valid,
        }
      end, qflist.items),
    }
  end
  return { ret, pos }
end

M.on_pre_load = function(data)
  local lists, pos = data[1], data[2]
  if not (lists and pos) then
    if not data.filename then
      return
    end
    -- migration
    lists, pos = { items = data }, 1
  end
  vim.fn.setqflist({}, "f") -- ensure lists are always cleared
  vim.iter(lists):each(function(qflist)
    vim.fn.setqflist({}, " ", qflist)
  end)
  vim.cmd.chistory({ count = pos })
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

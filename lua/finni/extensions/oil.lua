---@type finni.core.Extension
local M = {}

function M.is_win_supported(_winid, bufnr)
  return vim.bo[bufnr].filetype == "oil"
end

function M.save_win(_winid)
  -- We don't need to remember anything in particular, we can
  -- rely on the regular window data only.
  return {}
end

function M.load_win(winid, config, win)
  require("oil").open(win.bufname or config.bufname, nil, function()
    vim.api.nvim_win_call(winid, function()
      ---@diagnostic disable-next-line: need-check-nil
      -- Oil loads asynchronously, so view restoration by Finni fails.
      -- Workaround by restoring again in oil callback.
      vim.fn.winrestview(win.view or { lnum = win.cursor[1], col = win.cursor[2] })
    end)
  end)
end

return M

---@using continuity.tests
---@type continuity.tests.helpers
local helpers = dofile("tests/helpers.lua")
local eq, ne, ok, no, match =
  helpers.ex.eq, helpers.ex.ne, helpers.ex.ok, helpers.ex.no, helpers.ex.match

local T, child = helpers.new_test({ config = { log = { level = "trace" } } })
local snapshot = child.mod("core.snapshot")

T["Basic snapshot works"] = function()
  -- Setup state
  child.cmd("edit .gitignore | balt README.md | call bufadd('not_listed')")
  child.type_keys("2j4l")

  local ss = child.get_snapshot()
  local buf = ss:buf("gitignore")
  local balt = ss:buf("README")
  local tab = ss:tab()
  local win = ss:win()

  -- Verify global data consistency
  eq(ss.global.cwd, vim.fn.getcwd())
  eq(ss.global.height, win.height + tab.options.cmdheight)
  eq(ss.global.width, win.width)
  eq(#ss.buffers, 2)
  eq(#ss.tabs, 1)
  eq(#ss:wins(), 1)
  no(tab.cwd, win.cwd)
  ne(buf.uuid, balt.uuid)

  -- Verify visible buffer consistency
  ok(buf.in_win == true, buf.loaded == true, buf.uuid, buf.options, buf.last_pos)
  ok(buf.options.buflisted == true, buf.options.modifiable == true, buf.options.readonly == false)
  no(buf.changelist, buf.marks, win.jumps) -- opt-in

  -- Verify alternate buffer
  no(balt.in_win, balt.loaded)
  eq(win.alt, ss:bufno(balt.name))

  -- Verify view
  ok(tab.current, win.current)
  eq(buf.last_pos, { 1, 0 }) -- only updated when buffer leaves window
  eq(win.cursor, { 3, 4 })
  match(win.bufname, "%.gitignore$")
  eq(win.bufuuid, buf.uuid)

  -- Restore in same instance with reset and ensure we reproduce the same snapshot
  snapshot.restore(ss, { reset = true })
  buf.last_pos = win.cursor -- buffer has left window, so it's updated by now
  eq(child.get_snapshot(), ss)

  -- Also test that restoration after restart reproduces the same state
  child.reset()
  snapshot.restore(ss)
  eq(child.get_snapshot(), ss)

  -- Also test that restoration in VimEnter reproduces the same state
  child.with({
    init = {
      function(data)
        vim.api.nvim_create_autocmd("VimEnter", {
          nested = true,
          once = true,
          callback = function()
            require("continuity.core.snapshot").restore(data)
          end,
        })
      end,
      ss,
    },
  }, function(init_child)
    eq(init_child.get_snapshot(), ss)
  end)
end

return T

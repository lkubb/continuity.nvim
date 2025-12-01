---@diagnostic disable: access-invisible, duplicate-set-field

---@type finni.tests.helpers
local helpers = dofile("tests/helpers.lua")
local eq = helpers.ex.eq

local T, child = helpers.new_test()
local layout = child.mod("core.layout")

T["Returns nested structure"] = function()
  layout.get_win_info = function(_tabnr, winid)
    return { win = winid }
  end
  local ret = layout.add_win_info_to_layout(0, {
    "col",
    {
      { "leaf", 1 },
      { "leaf", 2 },
    },
    ---@diagnostic disable-next-line: missing-parameter
  })
  eq({
    "col",
    {
      { "leaf", { win = 1 } },
      { "leaf", { win = 2 } },
    },
  }, ret)
end

T["Compacts structure when buffers are skipped"] = function()
  layout.get_win_info = function(_tabnr, winid)
    -- dev note: It's faster to define `wins` in the mocked function than dumping the upval
    ---@type table<integer, integer|false>
    local wins = {
      1,
      false,
      3,
    }
    return wins[winid]
  end
  local ret = layout.add_win_info_to_layout(0, {
    "col",
    {
      { "leaf", 1 },
      { "leaf", 2 },
      { "leaf", 3 },
    },
    ---@diagnostic disable-next-line: missing-parameter
  })
  eq({
    "col",
    {
      { "leaf", 1 },
      { "leaf", 3 },
    },
  }, ret)
end

return T

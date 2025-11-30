local MiniTest = require("mini.test")
local eq = MiniTest.expect.equality
local helpers = dofile("test/helpers.lua")

local child = MiniTest.new_child_neovim()

local new_buf = function()
  child.bo.ft = "json"
  child.type_keys("iline1<cr>line2<cr>line3<cr>line4<cr>line5<cr>line6<cr>line7<esc>gg")
end

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      child.restart({ "-u", "test/init.lua" })
      child.bo.readonly = false
      child.lua([[M = require('guttermarks.actions')]])
    end,
    post_once = child.stop,
  },
})

-- ============================================================================
-- set_mark() tests
-- ============================================================================
T["set_mark"] = MiniTest.new_set()

T["set_mark"]["sets local mark"] = function()
  new_buf()
  child.type_keys("gg")

  child.lua([[ M.set_mark('a') ]])

  local gutter = helpers.get_gutter(child)
  eq(#gutter, 1)
  eq(gutter[1][4]["sign_text"], "a ")
  eq(gutter[1][2], 0) -- line 1 (0-indexed)
end

T["set_mark"]["sets global mark"] = function()
  new_buf()
  child.type_keys("2G")

  child.lua([[ M.set_mark('A') ]])

  local gutter = helpers.get_gutter(child)
  eq(#gutter, 1)
  eq(gutter[1][4]["sign_text"], "A ")
  eq(gutter[1][2], 1) -- line 2 (0-indexed)
end

T["set_mark"]["sets mark at specific line and col"] = function()
  new_buf()

  local bufnr = child.api.nvim_get_current_buf()
  child.lua(string.format([[ M.set_mark('b', %d, 3, 0) ]], bufnr))

  local mark_pos = child.fn.getpos("'b")
  eq(mark_pos[2], 3) -- line 3
  eq(mark_pos[3], 1) -- col 1 (1-indexed in getpos)
end

T["set_mark"]["rejects invalid mark character"] = function()
  new_buf()

  local result = child.lua_get([[ M.set_mark('1') ]])
  eq(result, false)
end

T["set_mark"]["overwrites existing mark"] = function()
  new_buf()
  child.type_keys("gg")
  child.type_keys("mc")

  child.type_keys("3G")
  child.lua([[ M.set_mark('c') ]])

  local mark_pos = child.fn.getpos("'c")
  eq(mark_pos[2], 3) -- should be on line 3 now
end

-- ============================================================================
-- set_auto_mark() tests
-- ============================================================================
T["set_auto_mark"] = MiniTest.new_set()

T["set_auto_mark"]["creates mark when line is empty"] = function()
  new_buf()
  child.type_keys("gg")

  local success, action, mark_char = unpack(child.lua_get([[ {M.set_auto_mark()} ]]))

  eq(success, true)
  eq(action, "created")
  eq(mark_char, "a") -- first available mark

  local gutter = helpers.get_gutter(child)
  eq(#gutter, 1)
  eq(gutter[1][4]["sign_text"], "a ")
end

T["set_auto_mark"]["deletes mark when line has mark"] = function()
  new_buf()
  child.type_keys("gg")
  child.type_keys("ma")

  local gutter = helpers.get_gutter(child)
  eq(#gutter, 1)

  local success, action, mark_char = unpack(child.lua_get([[ {M.set_auto_mark()} ]]))

  eq(success, true)
  eq(action, "deleted")
  eq(mark_char, "a")

  gutter = helpers.get_gutter(child)
  eq(#gutter, 0)
end

T["set_auto_mark"]["uses next available letter"] = function()
  new_buf()
  child.type_keys({ "gg", "ma", "j", "mb", "j" })

  local success, action, mark_char = unpack(child.lua_get([[ {M.set_auto_mark()} ]]))

  eq(success, true)
  eq(action, "created")
  eq(mark_char, "c") -- 'a' and 'b' already used
end

T["set_auto_mark"]["skips used marks and finds next available"] = function()
  new_buf()
  child.type_keys({ "gg", "ma", "j", "mc", "j" }) -- skip 'b'

  local success, action, mark_char = unpack(child.lua_get([[ {M.set_auto_mark()} ]]))

  eq(success, true)
  eq(action, "created")
  eq(mark_char, "b") -- finds 'b' which was skipped
end

T["set_auto_mark"]["handles all marks used"] = function()
  new_buf()

  -- Use lua to set all 26 marks programmatically
  child.lua([[
    for i = 1, 26 do
      local mark_char = string.char(string.byte("a") + i - 1)
      vim.api.nvim_buf_set_mark(0, mark_char, 1, 0, {})
    end
  ]])

  child.type_keys("2G") -- Move to line 2

  -- Try to set another mark when all are used
  local success, action = unpack(child.lua_get([[ {M.set_auto_mark()} ]]))

  eq(success, false)
  eq(action, "no_available_marks")
end

T["set_auto_mark"]["toggle on same line multiple times"] = function()
  new_buf()
  child.type_keys("gg")

  -- Create mark
  local result1 = child.lua_get([[ {M.set_auto_mark()} ]])
  eq(result1[2], "created")

  -- Delete mark
  local result2 = child.lua_get([[ {M.set_auto_mark()} ]])
  eq(result2[2], "deleted")

  -- Create mark again
  local result3 = child.lua_get([[ {M.set_auto_mark()} ]])
  eq(result3[2], "created")
end

-- ============================================================================
-- reorder_marks() tests
-- ============================================================================
T["reorder_marks"] = MiniTest.new_set()

T["reorder_marks"]["reorders marks alphabetically by line"] = function()
  new_buf()

  -- Set marks in random order: 'c' on line 1, 'a' on line 3, 'b' on line 2
  child.type_keys({ "gg", "mc", "2G", "mb", "3G", "ma" })

  local success, count = unpack(child.lua_get([[ {M.reorder_marks()} ]]))

  eq(success, true)
  eq(count, 3)

  -- Verify marks are now: 'a' on line 1, 'b' on line 2, 'c' on line 3
  local mark_a_pos = child.fn.getpos("'a")
  local mark_b_pos = child.fn.getpos("'b")
  local mark_c_pos = child.fn.getpos("'c")

  eq(mark_a_pos[2], 1)
  eq(mark_b_pos[2], 2)
  eq(mark_c_pos[2], 3)
end

T["reorder_marks"]["handles single mark"] = function()
  new_buf()
  child.type_keys({ "2G", "mz" })

  local success, count = unpack(child.lua_get([[ {M.reorder_marks()} ]]))

  eq(success, true)
  eq(count, 1)

  -- Single mark should become 'a' on same line
  local mark_pos = child.fn.getpos("'a")
  eq(mark_pos[2], 2)
end

T["reorder_marks"]["returns false when no marks"] = function()
  new_buf()

  local success, count = unpack(child.lua_get([[ {M.reorder_marks()} ]]))

  eq(success, false)
  eq(count, 0)
end

T["reorder_marks"]["preserves column positions"] = function()
  new_buf()
  child.type_keys({ "gg", "0", "ll", "ma", "2G", "0", "lll", "mb" })

  -- Store column positions before reorder
  local col_line1 = child.fn.getpos("'a")[3]
  local col_line2 = child.fn.getpos("'b")[3]

  child.lua([[ M.reorder_marks() ]])

  -- Check that columns are preserved (marks might be renamed)
  local new_mark1_pos = child.fn.getpos("'a")
  local new_mark2_pos = child.fn.getpos("'b")

  eq(new_mark1_pos[2], 1)
  eq(new_mark1_pos[3], col_line1)
  eq(new_mark2_pos[2], 2)
  eq(new_mark2_pos[3], col_line2)
end

T["reorder_marks"]["handles marks on same line (sorts by column)"] = function()
  new_buf()

  -- Set multiple marks on line 2 at different columns
  child.type_keys({ "2G", "0", "ll", "mb", "0", "l", "ma" })

  child.lua([[ M.reorder_marks() ]])

  -- Mark at earlier column should become 'a', later column should become 'b'
  local mark_a_pos = child.fn.getpos("'a")
  local mark_b_pos = child.fn.getpos("'b")

  eq(mark_a_pos[2], 2)
  eq(mark_b_pos[2], 2)
  -- Verify 'a' comes before 'b' in column order
  eq(mark_a_pos[3] < mark_b_pos[3], true)
end

T["reorder_marks"]["ignores global marks"] = function()
  new_buf()

  -- Set both local and global marks
  child.type_keys({ "gg", "mb", "2G", "mA", "3G", "ma" })

  child.lua([[ M.reorder_marks() ]])

  -- Global mark 'A' should remain unchanged
  local global_mark_pos = child.fn.getpos("'A")
  eq(global_mark_pos[2], 2)

  -- Local marks should be reordered
  local mark_a_pos = child.fn.getpos("'a")
  local mark_b_pos = child.fn.getpos("'b")
  eq(mark_a_pos[2], 1)
  eq(mark_b_pos[2], 3)
end

T["reorder_marks"]["invalidates cache"] = function()
  new_buf()
  child.type_keys({ "gg", "mc", "2G", "ma", "3G", "mb" })

  -- Ensure cache is populated
  child.lua([[ require('guttermarks').refresh() ]])

  -- Verify cache exists
  local bufnr = child.api.nvim_get_current_buf()
  local cache_exists = child.lua_get(string.format(
    [[ require('guttermarks')._marks_cache[%d] ~= nil ]],
    bufnr
  ))

  eq(cache_exists, true)

  -- Reorder marks (this should invalidate and recreate cache)
  child.lua([[ M.reorder_marks() ]])

  -- After reorder, gutter should reflect new mark names
  local gutter = helpers.get_gutter(child)
  eq(#gutter, 3)

  -- Verify marks are correctly ordered in gutter
  local signs = {}
  for _, mark in ipairs(gutter) do
    table.insert(signs, { line = mark[2] + 1, sign = mark[4]["sign_text"] })
  end
  table.sort(signs, function(a, b)
    return a.line < b.line
  end)

  eq(signs[1].sign, "a ")
  eq(signs[2].sign, "b ")
  eq(signs[3].sign, "c ")
end

-- ============================================================================
-- Navigation with count tests (enhanced functionality)
-- ============================================================================
T["navigation_with_count"] = MiniTest.new_set()

T["navigation_with_count"]["next_buf_mark with count 2"] = function()
  new_buf()
  child.type_keys({ "gg", "ma", "2G", "mb", "3G", "mc", "4G", "md", "gg" })

  child.lua([[ M.next_buf_mark(2) ]])

  eq(child.api.nvim_win_get_cursor(0)[1], 3) -- should jump to 2nd mark forward (line 2 is 1st, line 3 is 2nd)
end

T["navigation_with_count"]["next_buf_mark with count 3"] = function()
  new_buf()
  child.type_keys({ "gg", "ma", "2G", "mb", "3G", "mc", "4G", "md", "gg" })

  child.lua([[ M.next_buf_mark(3) ]])

  eq(child.api.nvim_win_get_cursor(0)[1], 4) -- jumps to 3rd mark forward
end

T["navigation_with_count"]["prev_buf_mark with count 2"] = function()
  new_buf()
  child.type_keys({ "gg", "ma", "2G", "mb", "3G", "mc", "4G", "md", "5G" })

  child.lua([[ M.prev_buf_mark(2) ]])

  eq(child.api.nvim_win_get_cursor(0)[1], 3) -- should jump backward 2 marks to 'c'
end

T["navigation_with_count"]["next_buf_mark count exceeds available marks"] = function()
  new_buf()
  child.type_keys({ "gg", "ma", "2G", "mb", "gg" })

  child.lua([[ M.next_buf_mark(5) ]]) -- only 2 marks ahead

  eq(child.api.nvim_win_get_cursor(0)[1], 2) -- should go to last available mark
end

T["navigation_with_count"]["prev_buf_mark count exceeds available marks"] = function()
  new_buf()
  child.type_keys({ "gg", "ma", "2G", "mb", "3G", "mc", "5G" })

  child.lua([[ M.prev_buf_mark(5) ]]) -- only 3 marks behind

  eq(child.api.nvim_win_get_cursor(0)[1], 1) -- should go to first available mark
end

T["navigation_with_count"]["backwards compatibility with opts as first arg"] = function()
  new_buf()
  child.type_keys({ "gg", "ma", "2G", "mB", "3G", "mc", "gg" })

  -- Old calling style: opts as first argument
  child.lua([[ M.next_buf_mark({ global_mark = false }) ]])

  eq(child.api.nvim_win_get_cursor(0)[1], 3) -- should skip global 'B' and jump to 'c'
end

T["navigation_with_count"]["count with opts"] = function()
  new_buf()
  child.type_keys({ "gg", "ma", "2G", "mB", "3G", "mc", "4G", "mD", "5G", "me", "gg" })

  -- New calling style: count and opts
  child.lua([[ M.next_buf_mark(2, { global_mark = false }) ]])

  eq(child.api.nvim_win_get_cursor(0)[1], 5) -- should skip global marks and count only local (ma at line 1, mc at line 3, me at line 5)
end

return T

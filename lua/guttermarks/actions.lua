local M = {}

---Action to delete a mark at current cursor position
---or selected position
---@param bufnr number|nil - buffer number to use (default to current buffer)
---@param line number|nil - line number to use (default to cursor line)
M.delete_mark = function(bufnr, line)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  line = line or vim.api.nvim_win_get_cursor(0)[1]

  for _, m in ipairs(vim.fn.getmarklist(bufnr)) do
    if m.pos[2] == line and m.mark:match("^'[a-z]") then
      vim.api.nvim_buf_del_mark(bufnr, m.mark:sub(2))
    end
  end

  for _, m in ipairs(vim.fn.getmarklist()) do
    if m.pos[1] == bufnr and m.pos[2] == line and m.mark:match("^'[A-Z]") then
      vim.api.nvim_del_mark(m.mark:sub(2))
    end
  end
  require("guttermarks").refresh()
end

---Set a mark at a specific position
---@param mark_char string The mark character (a-z for local, A-Z for global)
---@param bufnr? number Buffer number (defaults to current buffer)
---@param line? number Line number (defaults to cursor line)
---@param col? number Column number (defaults to cursor column)
---@return boolean success Whether the mark was set successfully
function M.set_mark(mark_char, bufnr, line, col)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if not line or not col then
    local cursor = vim.api.nvim_win_get_cursor(0)
    line = line or cursor[1]
    col = col or cursor[2]
  end

  -- Check if it's a valid mark character
  local is_lower = mark_char:match("^[a-z]$")
  local is_upper = mark_char:match("^[A-Z]$")

  if is_lower then
    -- Set local mark (a-z)
    vim.api.nvim_buf_set_mark(bufnr, mark_char, line, col, {})
    require("guttermarks").refresh()
    return true
  elseif is_upper then
    -- Set global mark (A-Z)
    vim.api.nvim_buf_set_mark(0, mark_char, line, col, {})
    require("guttermarks").refresh()
    return true
  else
    vim.notify("Invalid mark character: " .. mark_char, vim.log.levels.WARN)
    return false
  end
end

---Automatically set or toggle a mark at the current cursor position
---If there's a mark on the current line, delete it.
---If there's no mark, create a new one using the next available letter (a-z).
---@param bufnr? number Buffer number (defaults to current buffer)
---@param line? number Line number (defaults to cursor line)
---@return boolean success Whether the operation was successful
---@return string? action The action taken: "deleted", "created", or "no_available_marks"
---@return string? mark_char The mark character that was deleted or created
function M.set_auto_mark(bufnr, line)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  line = line or vim.api.nvim_win_get_cursor(0)[1]

  -- Check if there's already a mark on this line
  local marks_on_line = {}
  for _, m in ipairs(vim.fn.getmarklist(bufnr)) do
    if m.pos[2] == line and m.mark:match("^'[a-z]") then
      table.insert(marks_on_line, m.mark:sub(2))
    end
  end

  -- If there's a mark on this line, delete it
  if #marks_on_line > 0 then
    for _, mark_char in ipairs(marks_on_line) do
      vim.api.nvim_buf_del_mark(bufnr, mark_char)
    end
    require("guttermarks").refresh()
    return true, "deleted", marks_on_line[1]
  end

  -- Otherwise, find the next available mark letter
  local used_marks = {}
  for _, m in ipairs(vim.fn.getmarklist(bufnr)) do
    local mark_char = m.mark:sub(2)
    if mark_char:match("^[a-z]$") then
      used_marks[mark_char] = true
    end
  end

  -- Find the first available mark from a-z
  local next_mark = nil
  for i = string.byte("a"), string.byte("z") do
    local char = string.char(i)
    if not used_marks[char] then
      next_mark = char
      break
    end
  end

  -- If no marks available, notify user
  if not next_mark then
    vim.notify("No available marks (a-z all in use)", vim.log.levels.WARN)
    return false, "no_available_marks", nil
  end

  -- Set the mark
  local cursor = vim.api.nvim_win_get_cursor(0)
  vim.api.nvim_buf_set_mark(bufnr, next_mark, line, cursor[2], {})
  require("guttermarks").refresh()

  return true, "created", next_mark
end

---Reorder all local marks in the buffer in alphabetical order based on line numbers
---Marks will be reassigned as 'a', 'b', 'c', etc. from top to bottom of the buffer
---@param bufnr? number Buffer number (defaults to current buffer)
---@return boolean success Whether the operation was successful
---@return number count Number of marks reordered
function M.reorder_marks(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Collect all local marks in the buffer with their positions
  local marks = {}
  for _, m in ipairs(vim.fn.getmarklist(bufnr)) do
    local mark_char = m.mark:sub(2)
    if mark_char:match("^[a-z]$") then
      table.insert(marks, {
        char = mark_char,
        line = m.pos[2],
        col = m.pos[3] - 1, -- getmarklist returns 1-indexed, but nvim_buf_set_mark expects 0-indexed
      })
    end
  end

  -- If no marks, nothing to do
  if #marks == 0 then
    vim.notify("No marks to reorder", vim.log.levels.INFO)
    return false, 0
  end

  -- Sort marks by line number (and column as tiebreaker)
  table.sort(marks, function(a, b)
    if a.line == b.line then
      return a.col < b.col
    end
    return a.line < b.line
  end)

  -- Invalidate cache before bulk mark operations to avoid stale display
  local guttermarks = require("guttermarks")
  guttermarks._marks_cache[bufnr] = nil

  -- Delete all existing local marks
  for _, mark in ipairs(marks) do
    vim.api.nvim_buf_del_mark(bufnr, mark.char)
  end

  -- Reassign marks in alphabetical order
  local new_marks = {}
  for i, mark in ipairs(marks) do
    local new_char = string.char(string.byte("a") + i - 1)

    -- Check if we've run out of letters (more than 26 marks)
    if i > 26 then
      vim.notify("Warning: More than 26 marks found, only first 26 will be reordered", vim.log.levels.WARN)
      break
    end

    vim.api.nvim_buf_set_mark(bufnr, new_char, mark.line, mark.col, {})
    table.insert(new_marks, {
      old = mark.char,
      new = new_char,
      line = mark.line,
    })
  end

  -- Refresh gutter display
  require("guttermarks").refresh()

  -- Notify user of the reordering
  local count = #new_marks
  vim.notify(string.format("Reordered %d mark%s", count, count == 1 and "" or "s"), vim.log.levels.INFO)

  return true, count
end

---Action to send marks to quickfix list
---@param opts table|nil - options table with local_mark, global_mark, special_mark booleans
M.marks_to_quickfix = function(opts)
  opts = opts or {}
  local local_mark = opts.local_mark ~= false
  local global_mark = opts.global_mark ~= false
  local special_mark = opts.special_mark == true

  local utils = require("guttermarks.utils")
  local qf_items = {}

  if local_mark then
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(bufnr) then
        local buffer_marks = vim.fn.getmarklist(bufnr)
        for _, mark in ipairs(buffer_marks) do
          local mark_name = mark.mark:sub(2)

          if utils.is_lower(mark_name) then
            local text = string.format("Mark %s (Local)", mark_name)
            local filename = vim.api.nvim_buf_get_name(bufnr)

            table.insert(qf_items, {
              bufnr = bufnr,
              filename = filename,
              lnum = mark.pos[2],
              col = mark.pos[3],
              text = text,
            })
          end
        end
      end
    end
  end

  local marks = vim.fn.getmarklist()
  for _, mark in ipairs(marks) do
    local mark_name = mark.mark:sub(2)
    local ext = ""
    local should_include = false

    if utils.is_upper(mark_name) then
      ext = " (Global)"
      should_include = global_mark
    elseif not utils.is_letter(mark_name) then
      ext = " (Special)"
      should_include = special_mark
    end

    if should_include then
      local text = string.format("Mark %s%s", mark_name, ext)

      table.insert(qf_items, {
        bufnr = mark.pos[1],
        filename = mark.file,
        lnum = mark.pos[2],
        col = mark.pos[3],
        text = text,
      })
    end
  end

  vim.fn.setqflist(qf_items, "r")
end
---@param direction "forward"|"backward" - search forward or backward
---@param count number - number of marks to jump
---@param opts table|nil - options table with local_mark, global_mark, wrap booleans
local function navigate_buf_mark(direction, count, opts)
  opts = opts or {}
  local local_mark = opts.local_mark ~= false
  local global_mark = opts.global_mark ~= false
  local wrap = opts.wrap ~= false

  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor[1]
  local current_col = cursor[2]

  local all_marks = {}

  if local_mark then
    for _, m in ipairs(vim.fn.getmarklist(bufnr)) do
      if m.mark:match("^'[a-z]") then
        table.insert(all_marks, { line = m.pos[2], col = m.pos[3] - 1, mark = m.mark:sub(2) })
      end
    end
  end

  if global_mark then
    for _, m in ipairs(vim.fn.getmarklist()) do
      if m.pos[1] == bufnr and m.mark:match("^'[A-Z]") then
        table.insert(all_marks, { line = m.pos[2], col = m.pos[3] - 1, mark = m.mark:sub(2) })
      end
    end
  end

  table.sort(all_marks, function(a, b)
    if a.line ~= b.line then
      return a.line < b.line
    end
    return a.col < b.col
  end)

  -- Find the nth mark in the requested direction
  local target_mark = nil
  if direction == "forward" then
    local found = 0
    for _, m in ipairs(all_marks) do
      if m.line > current_line or (m.line == current_line and m.col > current_col) then
        found = found + 1
        if found == count then
          target_mark = m
          break
        end
      end
    end
    if not target_mark and wrap and #all_marks > 0 then
      target_mark = all_marks[math.min(count, #all_marks)]
    end
  else
    local found = 0
    for i = #all_marks, 1, -1 do
      local m = all_marks[i]
      if m.line < current_line or (m.line == current_line and m.col < current_col) then
        found = found + 1
        if found == count then
          target_mark = m
          break
        end
      end
    end
    if not target_mark and wrap and #all_marks > 0 then
      target_mark = all_marks[math.max(#all_marks - count + 1, 1)]
    end
  end

  if target_mark then
    vim.cmd("normal! m'") -- push current position to jumplist
    vim.api.nvim_win_set_cursor(0, { target_mark.line, target_mark.col })
  end
end

---Navigate to the next mark in buffer (forward)
---@param count number|nil - number of marks to jump (default 1)
---@param opts table|nil - options table with local_mark, global_mark, wrap booleans
M.next_buf_mark = function(count, opts)
  if type(count) == "table" then
    opts = count
    count = 1
  end
  count = count or 1
  navigate_buf_mark("forward", count, opts)
end

---Navigate to the previous mark in buffer (backward)
---@param count number|nil - number of marks to jump (default 1)
---@param opts table|nil - options table with local_mark, global_mark, wrap booleans
M.prev_buf_mark = function(count, opts)
  if type(count) == "table" then
    opts = count
    count = 1
  end
  count = count or 1
  navigate_buf_mark("backward", count, opts)
end

return M

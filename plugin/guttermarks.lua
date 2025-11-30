if vim.g.loaded_guttermarks == 1 then
  return
end
vim.g.loaded_guttermarks = 1

local function guttermarks_command(opts)
  local subcommand = opts.fargs[1]

  if not subcommand or subcommand == "" then
    require("guttermarks").enable(true)
  elseif subcommand == "mark" then
    require("guttermarks.actions").set_auto_mark()
  elseif subcommand == "toggle" then
    require("guttermarks").toggle()
  elseif subcommand == "enable" then
    require("guttermarks").enable(true)
  elseif subcommand == "disable" then
    require("guttermarks").enable(false)
  elseif subcommand == "refresh" then
    require("guttermarks").refresh()
  elseif subcommand == "reorder" then
    require("guttermarks.actions").reorder_marks()
  elseif subcommand == "next" then
    local count = opts.count > 0 and opts.count or 1
    require("guttermarks.actions").next_buf_mark(count)
  elseif subcommand == "prev" then
    local count = opts.count > 0 and opts.count or 1
    require("guttermarks.actions").prev_buf_mark(count)
  elseif subcommand == "delete-all" then
    vim.cmd("delmarks!")
    require("guttermarks").refresh()
  else
    vim.notify("Marks: Unknown subcommand '" .. (subcommand or "") .. "'", vim.log.levels.ERROR)
    vim.notify("Available subcommands: mark, toggle, enable, disable, refresh, reorder, next, prev, delete-all", vim.log.levels.INFO)
  end
end

local function guttermarks_complete(arg_lead)
  local subcommands = { "mark", "toggle", "enable", "disable", "refresh", "reorder", "next", "prev", "delete-all" }
  local matches = {}

  for _, subcommand in ipairs(subcommands) do
    if vim.startswith(subcommand, arg_lead) then
      table.insert(matches, subcommand)
    end
  end

  return matches
end

vim.api.nvim_create_user_command("Marks", guttermarks_command, {
  nargs = "?",
  count = true,
  desc = "Marks plugin commands",
  complete = guttermarks_complete,
})

-- FIXME: This is calling setup twice!
-- NOTE: First time call is without any options or the default options.
-- NOTE: Second time if the user has any configuration in place - it's not desired behaviour.
-- if require("guttermarks").config == nil then
--   require("guttermarks").setup()
-- end

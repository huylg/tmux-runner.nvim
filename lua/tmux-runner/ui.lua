-- tmux-runner/ui.lua
-- User interface components for session selection and management

local config = require("tmux-runner.config")
local tmux = require("tmux-runner.tmux")
local pins = require("tmux-runner.pins")

local M = {}

---Format session info for display
---@param session table
---@return string
local function format_session(session)
  local cwd_display = session.cwd and session.cwd ~= "" and " - " .. session.cwd or ""
  return session.name .. cwd_display
end

---Select a tmux session using vim.ui.select
---@param opts? { managed_only?: boolean, prompt?: string }
---@param callback fun(session: table?)
function M.select_session(opts, callback)
  opts = opts or {}
  local managed_only = opts.managed_only ~= false -- default true

  local sessions = tmux.list_sessions(managed_only)

  -- Filter out current session to prevent self-attach
  local current_session = tmux.get_current_session()
  if current_session then
    sessions = vim.tbl_filter(function(s)
      return s.name ~= current_session
    end, sessions)
  end

  if #sessions == 0 then
    vim.notify("No tmux sessions found", vim.log.levels.WARN)
    callback(nil)
    return
  end

  vim.ui.select(sessions, {
    prompt = opts.prompt or "Select tmux session:",
    format_item = format_session,
  }, function(selected)
    callback(selected)
  end)
end

---Prompt user for a command to run
---@param opts? { prompt?: string, default?: string }
---@param callback fun(cmd: string?)
function M.prompt_command(opts, callback)
  opts = opts or {}

  vim.ui.input({
    prompt = opts.prompt or "Command to run: ",
    default = opts.default or "",
    completion = "shellcmd",
  }, function(input)
    if input and input ~= "" then
      callback(input)
    else
      callback(nil)
    end
  end)
end

---Prompt user for a session name
---@param opts? { prompt?: string, default?: string }
---@param callback fun(name: string?)
function M.prompt_session_name(opts, callback)
  opts = opts or {}

  vim.ui.input({
    prompt = opts.prompt or "Session name: ",
    default = opts.default or ("task_" .. os.time()),
  }, function(input)
    if input and input ~= "" then
      callback(tmux.sanitize_name(input))
    else
      callback(nil)
    end
  end)
end

---Show session details in a popup notification
---@param session table
function M.show_session_info(session)
  local lines = {
    "Session: " .. session.name,
    "Status: " .. (session.attached > 0 and "attached" or "detached"),
    "Windows: " .. session.windows,
    "Created: " .. os.date("%Y-%m-%d %H:%M:%S", session.created),
    "Managed: " .. (session.is_managed and "yes" or "no"),
  }

  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, {
    title = "Tmux Session Info",
  })
end

---Display list of sessions in a formatted way
---@param sessions table[]
function M.display_sessions(sessions)
  if #sessions == 0 then
    vim.notify("No tmux sessions found", vim.log.levels.INFO)
    return
  end

  local lines = { "Tmux Sessions:", "" }
  for i, session in ipairs(sessions) do
    local status_icon = session.attached > 0 and "●" or "○"
    local managed_icon = session.is_managed and "[M]" or "   "
    table.insert(lines, string.format(
      "  %s %s %s (%d windows)",
      status_icon,
      managed_icon,
      session.name,
      session.windows
    ))
  end

  table.insert(lines, "")
  table.insert(lines, "● = attached, ○ = detached, [M] = managed by nvim")

  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

---Confirm an action with the user
---@param message string
---@param callback fun(confirmed: boolean)
function M.confirm(message, callback)
  vim.ui.select({ "Yes", "No" }, {
    prompt = message,
  }, function(choice)
    callback(choice == "Yes")
  end)
end

---Format pinned item for display
---@param item table
---@return string
local function format_pinned_item(item)
  if item.type == "session" then
    local exists = tmux.session_exists(item.name)
    local status = exists and "●" or "○"
    return status .. " 📌 " .. item.name
  else
    local cwd_str = item.cwd and (" [" .. item.cwd .. "]") or ""
    return "⚡ " .. item.name .. " (" .. item.cmd .. ")" .. cwd_str
  end
end

---Select from pinned items
---@param callback fun(item: table?)
function M.select_pinned(callback)
  local pinned_items = pins.get_all()

  if #pinned_items == 0 then
    vim.notify("No pinned items found. Use :TmuxPin or :TmuxPinCommand to add pins.", vim.log.levels.WARN)
    callback(nil)
    return
  end

  vim.ui.select(pinned_items, {
    prompt = "Select pinned item:",
    format_item = format_pinned_item,
  }, function(selected)
    callback(selected)
  end)
end

---Edit the pins file
function M.edit_pins()
  local pins_file = vim.fn.stdpath("data") .. "/tmux-runner/pins.lua"

  -- Create directory if it doesn't exist
  local dir = vim.fn.fnamemodify(pins_file, ":h")
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end

  -- Check if file exists, create if not
  if vim.fn.filereadable(pins_file) == 0 then
    local pins_data = pins.list()
    pins.save(pins_data)
  end

  -- Open the file
  vim.cmd("edit " .. pins_file)

  -- Create an autocmd to reload pins when the file is written
  local group = vim.api.nvim_create_augroup("TmuxRunnerPins", { clear = true })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = pins_file,
    callback = function()
      vim.notify("Pins updated", vim.log.levels.INFO)
    end,
  })
end

---Confirm removing a pin
---@param message string
---@param callback fun(confirmed: boolean)
function M.confirm_remove_pin(message, callback)
  vim.ui.select({ "Yes", "No" }, {
    prompt = message,
  }, function(choice)
    callback(choice == "Yes")
  end)
end

---Select pinned item to toggle terminal
---@param callback fun(item: table?)
function M.select_pinned_to_toggle(callback)
  local pinned_items = pins.get_all()

  if #pinned_items == 0 then
    vim.notify("No pinned items found. Use :TmuxPin or :TmuxPinCommand to add pins.", vim.log.levels.WARN)
    callback(nil)
    return
  end

  vim.ui.select(pinned_items, {
    prompt = "Select pinned item to toggle:",
    format_item = format_pinned_item,
  }, function(selected)
    callback(selected)
  end)
end

return M

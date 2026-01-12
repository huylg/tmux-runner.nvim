-- tmux-runner/ui.lua
-- User interface components for session selection and management

local config = require("tmux-runner.config")
local tmux = require("tmux-runner.tmux")

local M = {}

---Format session info for display
---@param session table
---@return string
local function format_session(session)
  local status = session.attached > 0 and "attached" or "detached"
  local created = os.date("%H:%M:%S", session.created)
  return string.format("%s [%s] (%d windows, started %s)", session.name, status, session.windows, created)
end

---Select a tmux session using vim.ui.select
---@param opts? { managed_only?: boolean, prompt?: string }
---@param callback fun(session: table?)
function M.select_session(opts, callback)
  opts = opts or {}
  local managed_only = opts.managed_only ~= false -- default true

  local sessions = tmux.list_sessions(managed_only)

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

return M

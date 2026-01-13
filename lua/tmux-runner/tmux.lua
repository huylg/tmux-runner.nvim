-- tmux-runner/tmux.lua
-- Core tmux interaction module

local config = require("tmux-runner.config")

local M = {}

-- Internal state to track sessions created by this plugin
M._sessions = {}

---Check if tmux is available
---@return boolean
function M.is_available()
  local handle = io.popen(config.get().tmux_binary .. " -V 2>/dev/null")
  if handle then
    local result = handle:read("*a")
    handle:close()
    return result ~= nil and result ~= ""
  end
  return false
end

---Check if currently inside a tmux session
---@return boolean
function M.is_inside_tmux()
  return vim.env.TMUX ~= nil and vim.env.TMUX ~= ""
end

---Get the current tmux session name
---@return string? session_name
function M.get_current_session()
  if not M.is_inside_tmux() then
    return nil
  end

  local cmd = string.format("%s display-message -p '#S'", config.get().tmux_binary)
  local output = vim.fn.system(cmd)

  if vim.v.shell_error ~= 0 then
    return nil
  end

  return vim.trim(output)
end

---Sanitize session name (remove special characters)
---@param name string
---@return string
function M.sanitize_name(name)
  -- Replace spaces and special chars with underscores
  local sanitized = name:gsub("[^%w_-]", "_")
  -- Remove leading/trailing underscores
  sanitized = sanitized:gsub("^_+", ""):gsub("_+$", "")
  return sanitized
end

---Get full session name with prefix
---@param name string
---@return string
function M.get_full_name(name)
  return config.get().session_prefix .. M.sanitize_name(name)
end

---Check if a session exists
---@param session_name string Full session name
---@return boolean
function M.session_exists(session_name)
  local cmd = string.format("%s has-session -t %s 2>/dev/null", config.get().tmux_binary, vim.fn.shellescape(session_name))
  local exit_code = os.execute(cmd)
  return exit_code == 0
end

---Parse tmux list-sessions output
---@param output string[]
---@return table[] sessions
local function parse_sessions(output)
  local sessions = {}
  for _, line in ipairs(output) do
    if line and line ~= "" then
      -- Format: session_name:created_timestamp:attached_count:window_count
      local name, created, attached, windows = line:match("([^:]+):([^:]+):([^:]+):([^:]+)")
      if name then
        table.insert(sessions, {
          name = name,
          created = tonumber(created) or 0,
          attached = tonumber(attached) or 0,
          windows = tonumber(windows) or 1,
          is_managed = vim.startswith(name, config.get().session_prefix),
        })
      end
    end
  end
  return sessions
end

---List all tmux sessions
---@param managed_only? boolean Only return sessions created by this plugin
---@return table[] sessions
function M.list_sessions(managed_only)
  local cmd = string.format(
    "%s list-sessions -F '#{session_name}:#{session_created}:#{session_attached}:#{session_windows}' 2>/dev/null",
    config.get().tmux_binary
  )
  local output = vim.fn.systemlist(cmd)

  if vim.v.shell_error ~= 0 then
    return {}
  end

  local sessions = parse_sessions(output)

  if managed_only then
    sessions = vim.tbl_filter(function(s)
      return s.is_managed
    end, sessions)
  end

  return sessions
end

---Kill a tmux session
---@param session_name string Full session name
---@return boolean success
---@return string? error_message
function M.kill_session(session_name)
  if not M.session_exists(session_name) then
    return false, "Session does not exist: " .. session_name
  end

  local cmd = string.format(
    "%s kill-session -t %s",
    config.get().tmux_binary,
    vim.fn.shellescape(session_name)
  )

  vim.fn.system(cmd)

  if vim.v.shell_error ~= 0 then
    return false, "Failed to kill session"
  end

  -- Remove from tracked sessions
  M._sessions[session_name] = nil

  return true, nil
end

---Kill all managed sessions
---@return number killed_count
function M.kill_all_sessions()
  local sessions = M.list_sessions(true)
  local count = 0

  for _, session in ipairs(sessions) do
    local ok, _ = M.kill_session(session.name)
    if ok then
      count = count + 1
    end
  end

  return count
end

---Send keys to a tmux session
---@param session_name string Full session name
---@param keys string Keys to send
---@return boolean success
---@return string? error_message
function M.send_keys(session_name, keys)
  if not M.session_exists(session_name) then
    return false, "Session does not exist: " .. session_name
  end

  local cmd = string.format(
    "%s send-keys -t %s %s",
    config.get().tmux_binary,
    vim.fn.shellescape(session_name),
    vim.fn.shellescape(keys)
  )

  vim.fn.system(cmd)

  if vim.v.shell_error ~= 0 then
    return false, "Failed to send keys"
  end

  return true, nil
end

---Send keys followed by Enter to execute a command
---@param session_name string Full session name
---@param command string Command to execute
---@return boolean success
---@return string? error_message
function M.send_command(session_name, command)
  local ok, err = M.send_keys(session_name, command)
  if not ok then
    return false, err
  end

  -- Send Enter key
  return M.send_keys(session_name, "Enter")
end

---Create or attach to a tmux session
---If session exists, attach to it; otherwise create a new one
---@param name string Session name (without prefix)
---@param cwd? string Working directory for the session
---@return boolean success
---@return string? error_message
function M.new_session(name, cwd)
  local full_name = M.get_full_name(name)

  if M.session_exists(full_name) then
    return true, nil
  end

  local cmd = { config.get().tmux_binary, "new-session", "-d", "-s", full_name }
  
  if cwd then
    vim.list_extend(cmd, { "-c", cwd })
  end

  local result = vim.fn.system(cmd)

  if vim.v.shell_error ~= 0 then
    return false, "Failed to create tmux session: " .. vim.trim(result)
  end

  vim.fn.system({ config.get().tmux_binary, "set-option", "-t", full_name, "status", "off" })
  vim.fn.system({ config.get().tmux_binary, "set-option", "-t", full_name, "detach-on-destroy", "on" })

  return true, nil
end

---Attach to an existing tmux session
---@param session_name string Full session name
---@return boolean success
---@return string? error_message
function M.attach_session(session_name)
  if not M.session_exists(session_name) then
    return false, "Session does not exist: " .. session_name
  end

  local cmd = string.format(
    "%s attach-session -t %s",
    config.get().tmux_binary,
    vim.fn.shellescape(session_name)
  )

  vim.fn.system(cmd)

  if vim.v.shell_error ~= 0 then
    return false, "Failed to attach to session"
  end

  return true, nil
end

return M

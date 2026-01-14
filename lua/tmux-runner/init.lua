-- tmux-runner/init.lua
-- Main entry point for tmux-runner plugin

local M = {}

-- Lazy-load modules to avoid circular dependencies
local function get_config()
  return require("tmux-runner.config")
end

local function get_tmux()
  return require("tmux-runner.tmux")
end

local function get_terminal()
  return require("tmux-runner.terminal")
end

local function get_ui()
  return require("tmux-runner.ui")
end

---Setup the plugin with user configuration
---@param opts? TmuxRunnerConfig
function M.setup(opts)
  local config = get_config()
  config.setup(opts)

  -- Validate tmux is available
  local tmux = get_tmux()
  if not tmux.is_available() then
    vim.notify("tmux-runner: tmux not found in PATH!", vim.log.levels.ERROR)
    return
  end

  -- Create autocommands for cleanup
  local group = vim.api.nvim_create_augroup("TmuxRunner", { clear = true })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      -- Close all terminal buffers on exit
      get_terminal().close_all()
    end,
  })
end

---Run a command in a new background tmux session
---@param cmd string Command to run
---@param name? string Optional session name
---@return boolean success
---@return string? session_name
function M.run(cmd, name)
  local tmux = get_tmux()
  local config = get_config()

  local base_cmd = cmd:match("%S+")
  name = name or tmux.sanitize_name(base_cmd)

  local pwd = vim.fn.getcwd():match("([^/]+)$") or vim.fn.getcwd()
  pwd = tmux.sanitize_name(pwd)
  name = pwd .. "_" .. name

  local full_name = tmux.get_full_name(name)
  
  local ok, err = tmux.new_session(name, nil, cmd)
  if not ok then
    vim.notify("tmux-runner: " .. (err or "Failed to create session"), vim.log.levels.ERROR)
    return false, nil
  end

  vim.notify("Started session: " .. full_name, vim.log.levels.INFO)

  -- Auto-attach if configured
  if config.get().attach_on_create then
    get_terminal().attach(full_name)
  end

  return true, full_name
end

---Run multiple commands in separate background sessions
---@param cmds string[] List of commands to run
---@return number started_count
function M.run_multiple(cmds)
  local count = 0
  local base_time = os.time()

  for i, cmd in ipairs(cmds) do
    local name = string.format("multi_%d_%d", i, base_time)
    local ok, _ = M.run(cmd, name)
    if ok then
      count = count + 1
    end
  end

  vim.notify(string.format("Started %d/%d sessions", count, #cmds), vim.log.levels.INFO)
  return count
end

---Attach to a tmux session in a terminal buffer
---@param session_name string Full session name
---@param opts? { split?: "horizontal"|"vertical"|"float"|"current", size?: number }
---@return boolean success
function M.attach(session_name, opts)
  local terminal = get_terminal()

  local bufnr, err = terminal.attach(session_name, opts)
  if not bufnr then
    vim.notify("tmux-runner: " .. (err or "Failed to attach"), vim.log.levels.ERROR)
    return false
  end

  return true
end

---Interactive: select a session and attach to it
function M.select_and_attach()
  local ui = get_ui()

  ui.select_session({ managed_only = true }, function(session)
    if session then
      M.attach(session.name)
    end
  end)
end

---List all tmux sessions
---@param managed_only? boolean Only show sessions created by this plugin
function M.list(managed_only)
  local tmux = get_tmux()
  local ui = get_ui()

  local sessions = tmux.list_sessions(managed_only)
  ui.display_sessions(sessions)
end

---Kill a tmux session
---@param session_name string Full session name
---@return boolean success
function M.kill(session_name)
  local tmux = get_tmux()
  local terminal = get_terminal()

  -- Close terminal buffer if open
  terminal.close(session_name)

  local ok, err = tmux.kill_session(session_name)
  if not ok then
    vim.notify("tmux-runner: " .. (err or "Failed to kill session"), vim.log.levels.ERROR)
    return false
  end

  vim.notify("Killed session: " .. session_name, vim.log.levels.INFO)
  return true
end

---Interactive: select a session and kill it
function M.select_and_kill()
  local ui = get_ui()

  ui.select_session({ managed_only = false, prompt = "Select session to kill:" }, function(session)
    if session then
      ui.confirm("Kill session '" .. session.name .. "'?", function(confirmed)
        if confirmed then
          M.kill(session.name)
        end
      end)
    end
  end)
end

---Kill all managed sessions
---@return number killed_count
function M.kill_all()
  local tmux = get_tmux()
  local terminal = get_terminal()

  -- Close all terminal buffers first
  terminal.close_all()

  local count = tmux.kill_all_sessions()
  vim.notify(string.format("Killed %d sessions", count), vim.log.levels.INFO)
  return count
end

---Toggle terminal visibility for a session
---@param session_name? string Full session name (uses interactive select if not provided)
function M.toggle(session_name)
  local terminal = get_terminal()
  local ui = get_ui()

  if session_name and session_name ~= "" then
    terminal.toggle(session_name)
  else
    ui.select_session({ managed_only = true }, function(session)
      if session then
        terminal.toggle(session.name)
      end
    end)
  end
end

---Send keys to a tmux session
---@param session_name string Full session name
---@param keys string Keys to send
---@return boolean success
function M.send(session_name, keys)
  local tmux = get_tmux()

  local ok, err = tmux.send_keys(session_name, keys)
  if not ok then
    vim.notify("tmux-runner: " .. (err or "Failed to send keys"), vim.log.levels.ERROR)
    return false
  end

  return true
end

---Send a command (keys + Enter) to a tmux session
---@param session_name string Full session name
---@param command string Command to execute
---@return boolean success
function M.send_command(session_name, command)
  local tmux = get_tmux()

  local ok, err = tmux.send_command(session_name, command)
  if not ok then
    vim.notify("tmux-runner: " .. (err or "Failed to send command"), vim.log.levels.ERROR)
    return false
  end

  return true
end

---Interactive: prompt for command and run it
function M.prompt_and_run()
  local ui = get_ui()

  ui.prompt_command({}, function(cmd)
    if cmd then
      ui.prompt_session_name({}, function(name)
        if name then
          M.run(cmd, name)
        end
      end)
    end
  end)
end

---Check if tmux is available
---@return boolean
function M.is_available()
  return get_tmux().is_available()
end

---Get the list of sessions (programmatic access)
---@param managed_only? boolean
---@return table[]
function M.get_sessions(managed_only)
  return get_tmux().list_sessions(managed_only)
end

return M

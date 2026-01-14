-- tmux-runner/pins.lua
-- Pinned sessions and commands management

local config = require("tmux-runner.config")
local tmux = require("tmux-runner.tmux")

local M = {}

-- Path to pins file
local function get_pins_file()
  local data_dir = vim.fn.stdpath("data")
  return data_dir .. "/tmux-runner/pins.lua"
end

-- Get default pins structure
local function get_default_pins()
  return {
    sessions = {},
    commands = {},
  }
end

---Load pins from file
---@return table pins
function M.load()
  local pins_file = get_pins_file()

  -- Check if file exists
  local f = io.open(pins_file, "r")
  if not f then
    return get_default_pins()
  end

  local content = f:read("*a")
  f:close()

  -- Load and execute the Lua file
  local ok, pins = pcall(loadstring(content))
  if not ok or type(pins) ~= "table" then
    vim.notify("tmux-runner: Failed to load pins file, using defaults", vim.log.levels.WARN)
    return get_default_pins()
  end

  -- Ensure structure is correct
  if type(pins.sessions) ~= "table" then
    pins.sessions = {}
  end
  if type(pins.commands) ~= "table" then
    pins.commands = {}
  end

  return pins
end

---Save pins to file
---@param pins table
---@return boolean success
function M.save(pins)
  local pins_file = get_pins_file()
  local dir = vim.fn.fnamemodify(pins_file, ":h")

  -- Create directory if it doesn't exist
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end

  -- Generate Lua code
  local content = "return {\n"
  content = content .. "  sessions = {\n"
  for i, session in ipairs(pins.sessions) do
    content = content .. '    "' .. session .. '"' .. (i < #pins.sessions and ",\n" or "\n")
  end
  content = content .. "  },\n"
  content = content .. "  commands = {\n"
  for i, cmd in ipairs(pins.commands) do
    content = content .. "    { "
    content = content .. 'name = "' .. cmd.name .. '", '
    content = content .. 'cmd = "' .. cmd.cmd:gsub('"', '\\"') .. '"'
    if cmd.cwd then
      content = content .. ', cwd = "' .. cmd.cwd .. '"'
    else
      content = content .. ", cwd = nil"
    end
    content = content .. " }" .. (i < #pins.commands and ",\n" or "\n")
  end
  content = content .. "  }\n"
  content = content .. "}\n"

  local f = io.open(pins_file, "w")
  if not f then
    return false
  end

  f:write(content)
  f:close()

  return true
end

---Pin an existing session
---@param session_name string Full session name
---@return boolean success
function M.add_session(session_name)
  local pins = M.load()

  -- Check if already pinned
  for _, s in ipairs(pins.sessions) do
    if s == session_name then
      vim.notify("Session already pinned: " .. session_name, vim.log.levels.WARN)
      return false
    end
  end

  table.insert(pins.sessions, session_name)
  return M.save(pins)
end

---Pin a command
---@param name string Name for the command
---@param cmd string Command to run
---@param cwd? string Working directory
---@return boolean success
function M.add_command(name, cmd, cwd)
  local pins = M.load()

  -- Check if command name already exists
  for _, c in ipairs(pins.commands) do
    if c.name == name then
      vim.notify("Command already pinned: " .. name, vim.log.levels.WARN)
      return false
    end
  end

  table.insert(pins.commands, {
    name = name,
    cmd = cmd,
    cwd = cwd,
  })
  return M.save(pins)
end

---Remove a pin by name or index
---@param identifier string|number Session name, command name, or numeric index
---@return boolean success
function M.remove(identifier)
  local pins = M.load()
  local removed = false

  if type(identifier) == "number" then
    -- Remove by index (across sessions and commands)
    local total_count = #pins.sessions + #pins.commands
    if identifier < 1 or identifier > total_count then
      vim.notify("Invalid pin index", vim.log.levels.ERROR)
      return false
    end

    if identifier <= #pins.sessions then
      table.remove(pins.sessions, identifier)
      removed = true
    else
      table.remove(pins.commands, identifier - #pins.sessions)
      removed = true
    end
  else
    -- Remove by name
    for i, session in ipairs(pins.sessions) do
      if session == identifier then
        table.remove(pins.sessions, i)
        removed = true
        break
      end
    end

    if not removed then
      for i, cmd in ipairs(pins.commands) do
        if cmd.name == identifier then
          table.remove(pins.commands, i)
          removed = true
          break
        end
      end
    end
  end

  if removed then
    M.save(pins)
    return true
  else
    vim.notify("Pin not found: " .. tostring(identifier), vim.log.levels.WARN)
    return false
  end
end

---List all pins
---@return table { sessions: string[], commands: table[] }
function M.list()
  return M.load()
end

---Get all pins with type and index info for display
---@return table[] { type: "session"|"command", name: string, cmd?: string, cwd?: string, index: number }
function M.get_all()
  local pins = M.load()
  local result = {}

  for i, session in ipairs(pins.sessions) do
    table.insert(result, {
      type = "session",
      name = session,
      index = i,
    })
  end

  for i, cmd in ipairs(pins.commands) do
    table.insert(result, {
      type = "command",
      name = cmd.name,
      cmd = cmd.cmd,
      cwd = cmd.cwd,
      index = #pins.sessions + i,
    })
  end

  return result
end

---Find a pin by name
---@param name string Session name or command name
---@return table? { type: "session"|"command", name: string, cmd?: string, cwd?: string, index: number }
function M.get_by_name(name)
  local pins = M.load()

  -- Check sessions
  for i, session in ipairs(pins.sessions) do
    if session == name then
      return {
        type = "session",
        name = session,
        index = i,
      }
    end
  end

  -- Check commands
  for i, cmd in ipairs(pins.commands) do
    if cmd.name == name then
      return {
        type = "command",
        name = cmd.name,
        cmd = cmd.cmd,
        cwd = cmd.cwd,
        index = #pins.sessions + i,
      }
    end
  end

  return nil
end

---Load config-based pinned commands into pins file
function M.load_config_commands()
  local cfg = config.get()
  local pinned_commands = cfg.pinned_commands or {}

  if #pinned_commands == 0 then
    return
  end

  local pins = M.load()

  -- Add commands from config
  for _, cmd_config in ipairs(pinned_commands) do
    local exists = false
    for _, cmd in ipairs(pins.commands) do
      if cmd.name == cmd_config.name then
        exists = true
        break
      end
    end

    if not exists then
      table.insert(pins.commands, {
        name = cmd_config.name,
        cmd = cmd_config.cmd,
        cwd = cmd_config.cwd,
      })
    end
  end

  M.save(pins)
end

return M

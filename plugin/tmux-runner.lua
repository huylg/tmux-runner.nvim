-- plugin/tmux-runner.lua
-- Auto-load file for command registration

-- Prevent double-loading
if vim.g.loaded_tmux_runner then
  return
end
vim.g.loaded_tmux_runner = true

-- User Commands

-- :TmuxRun <command> [name]
-- Run a command in a new background tmux session
vim.api.nvim_create_user_command("TmuxRun", function(opts)
  local args = opts.fargs
  if #args == 0 then
    vim.notify("Usage: TmuxRun <command> [session_name]", vim.log.levels.ERROR)
    return
  end

  local cmd = args[1]
  local name = args[2]

  -- If command contains spaces and was quoted, args[1] contains full command
  -- Otherwise join all args except last (if it looks like a name)
  if #args > 2 or (#args == 2 and not args[2]:match("^[%w_-]+$")) then
    cmd = table.concat(args, " ")
    name = nil
  end

  require("tmux-runner").run(cmd, name)
end, {
  nargs = "+",
  desc = "Run command in background tmux session",
  complete = "shellcmd",
})

-- :TmuxRunPrompt
-- Interactively prompt for command and session name
vim.api.nvim_create_user_command("TmuxRunPrompt", function()
  require("tmux-runner").prompt_and_run()
end, {
  desc = "Prompt for command and run in background tmux session",
})

-- :TmuxRunMultiple cmd1;cmd2;cmd3
-- Run multiple commands in separate sessions
vim.api.nvim_create_user_command("TmuxRunMultiple", function(opts)
  local input = opts.args
  if input == "" then
    vim.notify("Usage: TmuxRunMultiple cmd1;cmd2;cmd3", vim.log.levels.ERROR)
    return
  end

  -- Split by semicolon
  local cmds = vim.split(input, ";", { trimempty = true })
  for i, cmd in ipairs(cmds) do
    cmds[i] = vim.trim(cmd)
  end

  require("tmux-runner").run_multiple(cmds)
end, {
  nargs = "+",
  desc = "Run multiple commands in separate background sessions",
})

-- :TmuxAttach [session_name]
-- Attach to a tmux session in terminal buffer
vim.api.nvim_create_user_command("TmuxAttach", function(opts)
  local session = opts.args

  if session == "" then
    require("tmux-runner").select_and_attach()
  else
    require("tmux-runner").attach(session)
  end
end, {
  nargs = "?",
  desc = "Attach to tmux session in terminal buffer",
  complete = function()
    local sessions = require("tmux-runner").get_sessions(false)
    return vim.tbl_map(function(s)
      return s.name
    end, sessions)
  end,
})

-- :TmuxList [all]
-- List tmux sessions
vim.api.nvim_create_user_command("TmuxList", function(opts)
  local managed_only = opts.args ~= "all"
  require("tmux-runner").list(managed_only)
end, {
  nargs = "?",
  desc = "List tmux sessions (use 'all' to show all sessions)",
  complete = function()
    return { "all" }
  end,
})

-- :TmuxKill [session_name]
-- Kill a tmux session
vim.api.nvim_create_user_command("TmuxKill", function(opts)
  local session = opts.args

  if session == "" then
    require("tmux-runner").select_and_kill()
  else
    require("tmux-runner").kill(session)
  end
end, {
  nargs = "?",
  desc = "Kill a tmux session",
  complete = function()
    local sessions = require("tmux-runner").get_sessions(false)
    return vim.tbl_map(function(s)
      return s.name
    end, sessions)
  end,
})

-- :TmuxKillAll
-- Kill all managed sessions
vim.api.nvim_create_user_command("TmuxKillAll", function()
  require("tmux-runner").kill_all()
end, {
  desc = "Kill all managed tmux sessions",
})

-- :TmuxToggle [session_name]
-- Toggle terminal visibility for a session
vim.api.nvim_create_user_command("TmuxToggle", function(opts)
  require("tmux-runner").toggle(opts.args)
end, {
  nargs = "?",
  desc = "Toggle terminal for tmux session",
  complete = function()
    local sessions = require("tmux-runner").get_sessions(false)
    return vim.tbl_map(function(s)
      return s.name
    end, sessions)
  end,
})

-- :TmuxSend <session_name> <keys>
-- Send keys to a tmux session
vim.api.nvim_create_user_command("TmuxSend", function(opts)
  local args = opts.fargs
  if #args < 2 then
    vim.notify("Usage: TmuxSend <session_name> <keys>", vim.log.levels.ERROR)
    return
  end

  local session = args[1]
  local keys = table.concat(vim.list_slice(args, 2), " ")

  require("tmux-runner").send(session, keys)
end, {
  nargs = "+",
  desc = "Send keys to a tmux session",
  complete = function(_, cmdline, _)
    -- If we haven't completed the session name yet, complete it
    local args = vim.split(cmdline, "%s+")
    if #args <= 2 then
      local sessions = require("tmux-runner").get_sessions(false)
      return vim.tbl_map(function(s)
        return s.name
      end, sessions)
    end
    return {}
  end,
})

-- :TmuxSendCommand <session_name> <command>
-- Send a command (with Enter) to a tmux session
vim.api.nvim_create_user_command("TmuxSendCommand", function(opts)
  local args = opts.fargs
  if #args < 2 then
    vim.notify("Usage: TmuxSendCommand <session_name> <command>", vim.log.levels.ERROR)
    return
  end

  local session = args[1]
  local command = table.concat(vim.list_slice(args, 2), " ")

  require("tmux-runner").send_command(session, command)
end, {
  nargs = "+",
  desc = "Send command to a tmux session (with Enter)",
  complete = function(_, cmdline, _)
    local args = vim.split(cmdline, "%s+")
    if #args <= 2 then
      local sessions = require("tmux-runner").get_sessions(false)
      return vim.tbl_map(function(s)
        return s.name
      end, sessions)
    end
    return {}
  end,
})

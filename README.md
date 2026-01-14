# tmux-runner.nvim

A Neovim plugin that allows you to run multiple commands in background tmux sessions and attach to them via terminal buffers.

## Features

- 🚀 Run commands in background tmux sessions
- 📺 Attach to sessions via Neovim terminal buffers
- 🔄 Toggle terminal visibility
- 📋 List and manage sessions
- ⌨️ Send keys/commands to running sessions
- 🎨 Interactive session picker with `vim.ui.select`
- 📌 Pin sessions for quick access
- ⚡ Pin commands to run quickly with session auto-creation

## Requirements

- Neovim >= 0.8.0
- tmux installed and available in PATH

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "your-username/tmux-runner.nvim",
  config = function()
    require("tmux-runner").setup({
      -- your configuration here
    })
  end,
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "your-username/tmux-runner.nvim",
  config = function()
    require("tmux-runner").setup()
  end,
}
```

### Local Development

Add the plugin directory to your runtimepath:

```lua
vim.opt.runtimepath:prepend("/path/to/tmux-runner.nvim")
require("tmux-runner").setup()
```

## Configuration

```lua
require("tmux-runner").setup({
  -- Path to tmux binary
  tmux_binary = "tmux",

  -- Prefix for created session names
  session_prefix = "nvim_runner_",

  -- Default shell for new sessions
  default_shell = vim.o.shell,

  -- Auto-attach to session after creating it
  attach_on_create = false,

  -- Terminal split direction: "horizontal" or "vertical"
  split_direction = "horizontal",

  -- Terminal split size (rows for horizontal, cols for vertical)
  split_size = 15,

  -- Close terminal buffer when session ends
  close_on_exit = true,

  -- Focus terminal window when attaching
  focus_on_attach = true,

  -- Pre-defined commands to pin (available on startup)
  pinned_commands = {
    { name = "dev", cmd = "npm run dev", cwd = nil },
    { name = "test", cmd = "npm run test:watch", cwd = nil },
  },
})
```

## Commands

| Command | Description |
|---------|-------------|
| `:TmuxRun <cmd> [name]` | Run command in background tmux session |
| `:TmuxRunPrompt` | Interactively prompt for command and session name |
| `:TmuxRunMultiple cmd1;cmd2;cmd3` | Run multiple commands in separate sessions |
| `:TmuxAttach [session]` | Attach to session in terminal buffer (interactive if no name) |
| `:TmuxList [all]` | List sessions (managed only by default, 'all' for all) |
| `:TmuxKill [session]` | Kill a session (interactive if no name) |
| `:TmuxKillAll` | Kill all managed sessions |
| `:TmuxToggle [session]` | Toggle terminal visibility for session |
| `:TmuxSend <session> <keys>` | Send keys to a session |
| `:TmuxSendCommand <session> <cmd>` | Send command with Enter to a session |
| `:TmuxPin [session]` | Pin an existing session (interactive if no name) |
| `:TmuxPinCommand <cmd> [name]` | Run command, create session, then pin it |
| `:TmuxUnpin [name]` | Unpin a session or command (interactive if no name) |
| `:TmuxSelectPinned` | Select from pinned list and run/attach |
| `:TmuxEditPins` | Edit pinned sessions and commands |

## Lua API

```lua
local runner = require("tmux-runner")

-- Run a command in background
runner.run("npm run dev", "frontend")

-- Run multiple commands
runner.run_multiple({ "npm run dev", "npm run test:watch", "docker-compose up" })

-- Attach to a session
runner.attach("nvim_runner_frontend")

-- Interactive select and attach
runner.select_and_attach()

-- List sessions
runner.list()           -- managed sessions only
runner.list(false)      -- all sessions

-- Kill sessions
runner.kill("nvim_runner_frontend")
runner.kill_all()

-- Toggle terminal
runner.toggle("nvim_runner_frontend")

-- Send keys/commands
runner.send("nvim_runner_frontend", "C-c")  -- Ctrl+C
runner.send_command("nvim_runner_frontend", "echo hello")

-- Check if tmux is available
if runner.is_available() then
  -- ...
end

-- Get sessions programmatically
local sessions = runner.get_sessions()      -- managed only
local all_sessions = runner.get_sessions(false)  -- all

-- Pin sessions and commands
runner.pin_session("nvim_runner_frontend")  -- Pin existing session
runner.pin_command("npm run dev", "dev")    -- Run command and pin
runner.unpin("dev")                         -- Unpin by name
runner.select_pinned()                      -- Select and run/attach
runner.edit_pinned_list()                   -- Edit pins file manually
```

## Example Keybindings

```lua
-- Run last command
vim.keymap.set("n", "<leader>tr", ":TmuxRunPrompt<CR>", { desc = "Run command in tmux" })

-- List sessions
vim.keymap.set("n", "<leader>tl", ":TmuxList<CR>", { desc = "List tmux sessions" })

-- Attach to session
vim.keymap.set("n", "<leader>ta", ":TmuxAttach<CR>", { desc = "Attach to tmux session" })

-- Kill session
vim.keymap.set("n", "<leader>tk", ":TmuxKill<CR>", { desc = "Kill tmux session" })

-- Toggle terminal
vim.keymap.set("n", "<leader>tt", ":TmuxToggle<CR>", { desc = "Toggle tmux terminal" })

-- Pin sessions
vim.keymap.set("n", "<leader>tp", ":TmuxSelectPinned<CR>", { desc = "Select pinned session/command" })
```

## Pin Sessions & Commands

The pin feature allows you to quickly access frequently used sessions or commands.

### Pre-Pin Commands in Config

Define commands in your setup that will be available on startup:

```lua
require("tmux-runner").setup({
  pinned_commands = {
    { name = "dev", cmd = "npm run dev", cwd = nil },
    { name = "test", cmd = "npm run test:watch", cwd = nil },
    { name = "docker", cmd = "docker-compose up", cwd = nil },
  },
})
```

### Pin Existing Sessions

```vim
" Pin an existing session
:TmuxPin nvim_runner_frontend

" Interactive selection
:TmuxPin
" Select from available sessions to pin
```

### Pin After Running Commands

```vim
" Run command and pin the resulting session
:TmuxPinCommand npm run dev frontend

" Run without specifying name (auto-generated)
:TmuxPinCommand "npm run build && npm run serve"
```

### Select from Pinned List

```vim
" Select from all pinned items
:TmuxSelectPinned
" Shows:
"   ● 📌 nvim_runner_frontend      (attach to existing session)
"   ○ 📌 nvim_runner_backend       (killed session, still pinned)
"   ⚡ dev (npm run dev)           (run command and create session)
"   ⚡ test (npm run test:watch)   (run command and create session)
```

- **📌 Session pins**: Attach to existing tmux sessions (● = active, ○ = inactive)
- **⚡ Command pins**: Run the command, create a session, and attach

### Edit Pinned List Manually

```vim
" Open the pins file for manual editing
:TmuxEditPins
```

This opens `~/.local/share/nvim/tmux-runner/pins.lua`:

```lua
return {
  sessions = {
    "nvim_runner_frontend",
    "nvim_runner_backend",
  },
  commands = {
    { name = "dev", cmd = "npm run dev", cwd = nil },
    { name = "test", cmd = "npm run test:watch", cwd = nil },
  }
}
```

### Unpin Items

```vim
" Unpin by name
:TmuxUnpin dev

" Interactive selection
:TmuxUnpin
" Select item to unpin
```

## Use Cases

### Background Dev Server

```vim
:TmuxRun npm run dev frontend
:TmuxAttach nvim_runner_frontend
```

### Multiple Services

```vim
:TmuxRunMultiple docker-compose up;npm run dev;npm run test:watch
```

### Send Interrupt to Running Process

```lua
-- Send Ctrl+C to stop a process
require("tmux-runner").send("nvim_runner_frontend", "C-c")
```

### Restart a Service

```lua
local runner = require("tmux-runner")
runner.send("nvim_runner_frontend", "C-c")
runner.send_command("nvim_runner_frontend", "npm run dev")
```

## License

MIT

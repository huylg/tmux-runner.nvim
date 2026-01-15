# tmux-runner.nvim

A Neovim plugin that allows you to run multiple commands in background tmux sessions and attach to them via terminal buffers.

## Features

- 🚀 Run commands in background tmux sessions
- 📺 Attach to sessions via Neovim terminal buffers
- 🔍 Scroll and search through full tmux history
- 🔄 Toggle terminal visibility
- 📋 List and manage sessions
- ⌨️ Send keys/commands to running sessions
- 🎨 Interactive session picker with `vim.ui.select`

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
```

## Use Cases

### Terminal Scrolling and Search

When you attach to a tmux session, you can use normal mode to scroll and search through the full tmux history:

- Press `Esc` to exit terminal mode and enter normal mode (scrollback buffer)
- In normal mode, use `j/k`, `gg`, `G`, `/pattern`, `n/N` to navigate and search
- Press `i` or `a` to return to terminal mode for interaction
- Press `R` in normal mode to refresh the scrollback buffer with latest tmux content

 This uses `tmux capture-pane` to capture the full scrollback history from the tmux session, allowing you to search through past output that would otherwise be lost in the terminal buffer.

**Note:** Scrollback displays raw ANSI escape sequences (e.g., `[1;31m`) for color codes. For colored output, stay in terminal mode or press `i`/`a` to return. The scrollback is primarily for text search, not colored viewing.

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

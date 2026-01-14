-- tmux-runner/config.lua
-- Configuration management for tmux-runner plugin

local M = {}

---@class TmuxRunnerConfig
---@field tmux_binary string Path to tmux binary
---@field session_prefix string Prefix for created sessions
---@field default_shell string Default shell for new sessions
---@field attach_on_create boolean Auto-attach after creating session
---@field split_direction "horizontal"|"vertical" Terminal split direction
---@field split_size number Terminal split size (rows for horizontal, cols for vertical)
---@field close_on_exit boolean Close terminal buffer when session ends
---@field focus_on_attach boolean Focus terminal window when attaching
---@field pinned_commands {name: string, cmd: string, cwd?: string}[] Pre-pinned commands

---@type TmuxRunnerConfig
M.defaults = {
  tmux_binary = "tmux",
  session_prefix = "nvim_runner_",
  default_shell = vim.o.shell or "/bin/bash",
  attach_on_create = false,
  split_direction = "horizontal",
  split_size = 15,
  close_on_exit = true,
  focus_on_attach = true,
  pinned_commands = {},
}

---@type TmuxRunnerConfig
M.options = vim.deepcopy(M.defaults)

---Setup configuration with user options
---@param opts? TmuxRunnerConfig
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

---Get current configuration
---@return TmuxRunnerConfig
function M.get()
  return M.options
end

return M

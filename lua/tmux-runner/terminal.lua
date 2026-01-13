-- tmux-runner/terminal.lua
-- Terminal buffer management module

local config = require("tmux-runner.config")
local tmux = require("tmux-runner.tmux")

local M = {}

-- Track terminal buffers and their associated sessions
-- { [session_name] = { bufnr = number, winid = number, job_id = number } }
M._terminals = {}

---Create a terminal buffer attached to a tmux session
---@param session_name string Full session name
---@param opts? { split?: "horizontal"|"vertical"|"float"|"current", size?: number }
---@return number? bufnr
---@return string? error_message
function M.attach(session_name, opts)
  opts = opts or {}
  local cfg = config.get()

  -- Check if session exists
  if not tmux.session_exists(session_name) then
    return nil, "Session does not exist: " .. session_name
  end

  -- Prevent attaching to the current session
  local current_session = tmux.get_current_session()
  if current_session and current_session == session_name then
    return nil, "Cannot attach to current tmux session"
  end

  -- Check if we already have a terminal for this session
  local existing = M._terminals[session_name]
  if existing and vim.api.nvim_buf_is_valid(existing.bufnr) then
    -- Focus existing terminal
    M.focus(session_name)
    return existing.bufnr, nil
  end

  -- Determine split direction and size
  local split_dir = opts.split or cfg.split_direction
  local split_size = opts.size or cfg.split_size

  -- Create the split/window
  local winid
  if split_dir == "horizontal" then
    vim.cmd("botright " .. split_size .. "split")
    winid = vim.api.nvim_get_current_win()
  elseif split_dir == "vertical" then
    vim.cmd("botright " .. split_size .. "vsplit")
    winid = vim.api.nvim_get_current_win()
  elseif split_dir == "float" then
    winid = M._create_float_window()
  else -- "current"
    winid = vim.api.nvim_get_current_win()
  end

  -- Create new buffer
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(winid, bufnr)

  -- Set buffer options
  vim.api.nvim_buf_set_option(bufnr, "bufhidden", "hide")
  vim.api.nvim_buf_set_option(bufnr, "buflisted", false)
  vim.api.nvim_win_set_option(winid, "statusline", "")

  -- Build the attach command with chained set-option
  local attach_cmd = string.format(
    "%s attach-session -t %s \\; set-option -t %s status off \\; set-option -t %s detach-on-destroy on",
    config.get().tmux_binary,
    vim.fn.shellescape(session_name),
    vim.fn.shellescape(session_name),
    vim.fn.shellescape(session_name)
  )

  -- Start terminal
  local job_id = vim.fn.termopen(attach_cmd, {
    on_exit = function(_, exit_code, _)
      M._on_terminal_exit(session_name, bufnr, exit_code)
    end,
  })

  if job_id <= 0 then
    vim.api.nvim_buf_delete(bufnr, { force = true })
    return nil, "Failed to start terminal"
  end

  -- Store terminal info
  M._terminals[session_name] = {
    bufnr = bufnr,
    winid = winid,
    job_id = job_id,
  }

  -- Set buffer name for identification
  vim.api.nvim_buf_set_name(bufnr, "tmux://" .. session_name)

  -- Enter insert mode for immediate interaction
  if cfg.focus_on_attach then
    vim.cmd("startinsert")
  end

  return bufnr, nil
end

---Create a floating window
---@return number winid
function M._create_float_window()
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local bufnr = vim.api.nvim_create_buf(false, true)

  local winid = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Tmux Session ",
    title_pos = "center",
  })

  return winid
end

---Handle terminal exit
---@param session_name string
---@param bufnr number
---@param exit_code number
function M._on_terminal_exit(session_name, bufnr, exit_code)
  local cfg = config.get()

  -- Remove from tracking
  M._terminals[session_name] = nil

  -- Close buffer if configured
  if cfg.close_on_exit and vim.api.nvim_buf_is_valid(bufnr) then
    -- Schedule to avoid issues with callback context
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(bufnr) then
        -- Find and close any windows showing this buffer
        for _, winid in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == bufnr then
            vim.api.nvim_win_close(winid, true)
          end
        end
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end)
  end
end

---Focus a terminal window for a session
---@param session_name string
---@return boolean success
function M.focus(session_name)
  local term = M._terminals[session_name]
  if not term then
    return false
  end

  -- Check if window still exists and shows our buffer
  if vim.api.nvim_win_is_valid(term.winid) and vim.api.nvim_win_get_buf(term.winid) == term.bufnr then
    vim.api.nvim_set_current_win(term.winid)
    vim.cmd("startinsert")
    return true
  end

  -- Window closed, find buffer in another window or create new split
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(winid) == term.bufnr then
      vim.api.nvim_set_current_win(winid)
      M._terminals[session_name].winid = winid
      vim.cmd("startinsert")
      return true
    end
  end

  -- Buffer exists but not visible, show it in new split
  if vim.api.nvim_buf_is_valid(term.bufnr) then
    local cfg = config.get()
    if cfg.split_direction == "horizontal" then
      vim.cmd("botright " .. cfg.split_size .. "split")
    else
      vim.cmd("botright " .. cfg.split_size .. "vsplit")
    end
    vim.api.nvim_win_set_buf(0, term.bufnr)
    M._terminals[session_name].winid = vim.api.nvim_get_current_win()
    vim.cmd("startinsert")
    return true
  end

  return false
end

---Toggle terminal visibility for a session
---@param session_name string
---@return boolean is_visible
function M.toggle(session_name)
  local term = M._terminals[session_name]

  if not term or not vim.api.nvim_buf_is_valid(term.bufnr) then
    -- No terminal exists, create one if session exists
    if tmux.session_exists(session_name) then
      local bufnr, err = M.attach(session_name)
      return bufnr ~= nil
    end
    return false
  end

  -- Check if terminal is visible
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == term.bufnr then
      -- Terminal is visible, hide it
      vim.api.nvim_win_close(winid, false)
      return false
    end
  end

  -- Terminal not visible, show it
  M.focus(session_name)
  return true
end

---Close terminal for a session
---@param session_name string
---@return boolean success
function M.close(session_name)
  local term = M._terminals[session_name]
  if not term then
    return false
  end

  -- Close windows showing this buffer
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == term.bufnr then
      vim.api.nvim_win_close(winid, true)
    end
  end

  -- Delete the buffer (this will also stop the job)
  if vim.api.nvim_buf_is_valid(term.bufnr) then
    vim.api.nvim_buf_delete(term.bufnr, { force = true })
  end

  M._terminals[session_name] = nil
  return true
end

---Close all terminal buffers
function M.close_all()
  for session_name, _ in pairs(M._terminals) do
    M.close(session_name)
  end
end

---Get terminal info for a session
---@param session_name string
---@return table? terminal_info
function M.get_terminal(session_name)
  return M._terminals[session_name]
end

---Check if a terminal is open for a session
---@param session_name string
---@return boolean
function M.is_open(session_name)
  local term = M._terminals[session_name]
  return term ~= nil and vim.api.nvim_buf_is_valid(term.bufnr)
end

return M

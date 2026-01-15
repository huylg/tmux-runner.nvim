-- tmux-runner/terminal.lua
-- Terminal buffer management module

local config = require("tmux-runner.config")
local tmux = require("tmux-runner.tmux")

local M = {}

-- Track terminal buffers and their associated sessions
-- { [session_name] = { bufnr = number, winid = number, job_id = number } }
M._terminals = {}

-- Default window options for terminal buffers
local wo_defaults = {
  winhighlight = "",
  colorcolumn = "",
  cursorcolumn = false,
  cursorline = false,
  fillchars = "eob: ",
  list = false,
  listchars = "tab:  ",
  number = false,
  relativenumber = false,
  sidescrolloff = 0,
  signcolumn = "no",
  statuscolumn = "",
  spell = false,
  winbar = "",
  wrap = false,
}

-- Default window options for scrollback buffers
local wo_scrollback = {
  winhighlight = "",
  colorcolumn = "",
  cursorcolumn = false,
  cursorline = true,
  fillchars = "eob: ",
  list = false,
  listchars = "tab:  ",
  number = false,
  relativenumber = false,
  sidescrolloff = 0,
  signcolumn = "no",
  statuscolumn = "",
  spell = false,
  winbar = "",
  wrap = true,
}

-- Default buffer options
local bo_defaults = {
  swapfile = false,
  filetype = "tmux-terminal",
}

---Set window options
---@param winid number Window id
---@param opts table Window options to apply
local function set_wo(winid, opts)
  for k, v in pairs(opts) do
    vim.api.nvim_set_option_value(k, v, { win = winid, scope = "local" })
  end
end

---Set buffer options
---@param bufnr number Buffer id
---@param opts table Buffer options to apply
local function set_bo(bufnr, opts)
  for k, v in pairs(opts) do
    vim.api.nvim_set_option_value(k, v, { buf = bufnr, scope = "local" })
  end
end

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
  set_bo(bufnr, bo_defaults)
  vim.api.nvim_set_option_value("bufhidden", "hide", { buf = bufnr })
  vim.api.nvim_set_option_value("buflisted", false, { buf = bufnr })

  -- Set window options
  set_wo(winid, wo_defaults)
  vim.api.nvim_set_option_value("statusline", "", { win = winid, scope = "local" })

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
    scrollback_buf = nil,
    normal_mode = false,
  }

  -- Set buffer name for identification
  vim.api.nvim_buf_set_name(bufnr, "tmux://" .. session_name)

  -- Setup mode tracking for scrollback buffer
  M._setup_mode_tracking(session_name, bufnr)

  -- Add refresh keymap for scrollback
  vim.api.nvim_buf_set_keymap(bufnr, "n", "R", "", {
    noremap = true,
    callback = function()
      M._open_scrollback(session_name)
    end,
    desc = "Refresh scrollback",
  })

  -- Enter insert mode for immediate interaction
  if cfg.focus_on_attach then
    vim.cmd("startinsert")
  end

  return bufnr, nil
end

---Setup mode tracking for scrollback buffer
---@param session_name string
---@param bufnr number
function M._setup_mode_tracking(session_name, bufnr)
  local group = vim.api.nvim_create_augroup("TmuxRunner_" .. session_name, { clear = true })

  -- Track normal_mode state when leaving window
  vim.api.nvim_create_autocmd("WinLeave", {
    group = group,
    buffer = bufnr,
    callback = function()
      local term = M._terminals[session_name]
      if not term then
        return
      end
      if vim.api.nvim_get_current_win() == term.winid then
        term.normal_mode = vim.fn.mode() ~= "t"
      end
    end,
  })

  -- Restore mode when entering the terminal window
  vim.api.nvim_create_autocmd("WinEnter", {
    group = group,
    callback = function()
      local term = M._terminals[session_name]
      if not term or not term.winid or not vim.api.nvim_win_is_valid(term.winid) then
        return
      end
      if vim.api.nvim_get_current_win() ~= term.winid then
        return
      end
      local current_buf = vim.api.nvim_win_get_buf(term.winid)
      -- Only restore mode if we're in the terminal buffer
      if current_buf == term.bufnr then
        if term.normal_mode then
          vim.cmd.stopinsert()
        else
          vim.cmd.startinsert()
        end
      end
    end,
  })

  -- Open scrollback when leaving terminal mode
  vim.api.nvim_create_autocmd("TermLeave", {
    group = group,
    buffer = bufnr,
    callback = function()
      local term = M._terminals[session_name]
      if not term or not term.winid or not vim.api.nvim_win_is_valid(term.winid) then
        return
      end
      if vim.api.nvim_win_get_buf(term.winid) == bufnr then
        M._open_scrollback(session_name)
      end
    end,
  })

  -- Close scrollback when entering terminal mode
  vim.api.nvim_create_autocmd("TermEnter", {
    group = group,
    buffer = bufnr,
    callback = function()
      local term = M._terminals[session_name]
      if not term or not term.winid or not vim.api.nvim_win_is_valid(term.winid) then
        return
      end
      if vim.api.nvim_win_get_buf(term.winid) == term.bufnr then
        M._close_scrollback(session_name)
      end
    end,
  })

  -- Clean up scrollback buffer when terminal closes
  vim.api.nvim_create_autocmd("TermClose", {
    group = group,
    buffer = bufnr,
    callback = function()
      local term = M._terminals[session_name]
      if term and term.scrollback_buf and vim.api.nvim_buf_is_valid(term.scrollback_buf) then
        vim.api.nvim_buf_delete(term.scrollback_buf, { force = true })
      end
    end,
  })
end

---Open scrollback buffer with captured tmux content
---@param session_name string
function M._open_scrollback(session_name)
  local term = M._terminals[session_name]
  if not term then
    return
  end

  -- Capture tmux pane content with escape sequences, join wrapped lines
  local cfg = config.get()
  local cmd = string.format(
    "%s capture-pane -t %s -e -J -p -S -",
    cfg.tmux_binary,
    vim.fn.shellescape(session_name)
  )

  local output = vim.fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 or not output then
    return
  end

  -- Create or reuse scrollback buffer
  local scrollback_buf = term.scrollback_buf
  local is_new = not scrollback_buf or not vim.api.nvim_buf_is_valid(scrollback_buf)

  if is_new then
    scrollback_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = scrollback_buf })
    vim.api.nvim_set_option_value("buflisted", false, { buf = scrollback_buf })
    vim.api.nvim_set_option_value("filetype", "tmux-scrollback", { buf = scrollback_buf })
    vim.api.nvim_buf_set_name(scrollback_buf, "tmux-scrollback://" .. session_name)
    term.scrollback_buf = scrollback_buf
    term.scrollback_channel = nil

    -- Add keymaps to switch back to terminal
    vim.api.nvim_buf_set_keymap(scrollback_buf, "n", "i", "", {
      noremap = true,
      callback = function()
        -- Clear normal_mode so WinEnter won't stopinsert
        term.normal_mode = false
        M._close_scrollback(session_name)
        -- Enter terminal mode after switch
        vim.schedule(function()
          vim.cmd.startinsert()
        end)
      end,
      desc = "Return to terminal mode",
    })
    vim.api.nvim_buf_set_keymap(scrollback_buf, "n", "a", "", {
      noremap = true,
      callback = function()
        -- Clear normal_mode so WinEnter won't stopinsert
        term.normal_mode = false
        M._close_scrollback(session_name)
        -- Enter terminal mode after switch
        vim.schedule(function()
          vim.cmd.startinsert()
        end)
      end,
      desc = "Return to terminal mode",
    })
    vim.api.nvim_buf_set_keymap(scrollback_buf, "n", "R", "", {
      noremap = true,
      callback = function()
        M._open_scrollback(session_name)
      end,
      desc = "Refresh scrollback",
    })
  end

  -- Update buffer content (ANSI codes appear raw, scrollback is for text search)
  vim.api.nvim_buf_set_lines(scrollback_buf, 0, -1, false, output)

  -- Switch window to scrollback buffer
  if vim.api.nvim_win_is_valid(term.winid) then
    vim.api.nvim_win_set_buf(term.winid, scrollback_buf)

    -- Set window options for scrollback
    set_wo(term.winid, wo_scrollback)

    -- Auto-scroll to bottom
    vim.api.nvim_win_call(term.winid, function()
      vim.cmd("normal G")
    end)
  end
end

---Close scrollback and return to live terminal
---@param session_name string
function M._close_scrollback(session_name)
  local term = M._terminals[session_name]
  if not term or not term.bufnr then
    return
  end

  -- Check if we're currently showing the scrollback buffer
  if not term.winid or not vim.api.nvim_win_is_valid(term.winid) then
    return
  end

  local current_buf = vim.api.nvim_win_get_buf(term.winid)
  if current_buf ~= term.scrollback_buf then
    return
  end

  -- Switch back to terminal buffer
  vim.api.nvim_win_set_buf(term.winid, term.bufnr)

  -- Restore terminal window options
  set_wo(term.winid, wo_defaults)
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

  -- Clean up scrollback buffer
  if term.scrollback_buf and vim.api.nvim_buf_is_valid(term.scrollback_buf) then
    vim.api.nvim_buf_delete(term.scrollback_buf, { force = true })
  end

  -- Clear autocmds
  pcall(vim.api.nvim_clear_autocmds, { group = "TmuxRunner_" .. session_name })
  pcall(vim.api.nvim_del_augroup_by_id, vim.fn.getaugroupid("TmuxRunner_" .. session_name))

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

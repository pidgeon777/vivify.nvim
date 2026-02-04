---@class VivifyApi
---@field private _initialized boolean
local M = {}

local config = require("vivify.config")

---Check if running on Windows
---@return boolean
local function is_windows()
  return vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1
end

---Check if plenary is available
---@return boolean
local function has_plenary()
  local ok = pcall(require, "plenary.curl")
  return ok
end

---Percent-encode a filepath to match Python's urllib.parse.quote() with safe='/'.
---This means:
---  - "/" is preserved (NOT encoded)
---  - ":" IS encoded to %3A (unlike our previous implementation)
---  - All other special characters are encoded
---This matches exactly what vivify.vim does via py3eval('quote(path)').
---@param str string Filepath to encode
---@return string URL-encoded path segment (without leading slash)
local function percent_encode_path(str)
  if not str then
    return ""
  end
  -- Get absolute, normalized path
  str = vim.fn.fnamemodify(str, ":p")

  -- On Windows, ensure forward slashes
  if is_windows() then
    -- Convert \ to /
    str = str:gsub("\\", "/")
  end

  -- Percent encode everything except alphanumeric, -, _, ., ~, and /
  -- This matches Python's quote() with safe='/' (the default)
  -- IMPORTANT: ":" must be encoded as %3A to match vivify.vim behavior!
  str = str:gsub("([^%w%-%._~/])", function(c)
    return string.format("%%%02X", string.byte(c))
  end)

  return str
end

---Get the base URL for Vivify server
---@return string Base URL
local function get_base_url()
  -- Using localhost to match Chrome address bar
  return string.format("http://localhost:%d", config.get_port())
end

---Log debug message
---@param msg string Message to log
---@vararg any Additional format arguments
local function debug_log(msg, ...)
  if config.options.debug then
    local formatted = string.format(msg, ...)
    vim.schedule(function()
      vim.notify("[vivify.nvim] " .. formatted, vim.log.levels.DEBUG)
    end)
  end
end

---Execute async HTTP POST request using direct curl
---Uses jobstart with array to avoid console window flashing on Windows
---@param url string Full URL
---@param data table Data to send as JSON
local function async_post(url, data)
  local json_data = vim.fn.json_encode(data)

  debug_log("POST %s (data size: %d bytes)", url, #json_data)

  -- Direct curl call. In Neovim, jobstart with an array doesn't spawn a window.
  -- We don't use server_ready gates to ensure requests are always attempted.
  local job_id = vim.fn.jobstart({
    "curl",
    "-s",
    "-X", "POST",
    "-H", "Content-Type: application/json",
    "--data", "@-",
    url,
  })

  if job_id > 0 then
    vim.fn.chansend(job_id, json_data)
    vim.fn.chanclose(job_id, "stdin")
  end
end

---Sync buffer content to Vivify viewer
---@param bufnr number|nil Buffer number (default: current)
function M.sync_content(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Check filetype dynamically (matching original behavior)
  local ft = vim.bo[bufnr].filetype
  if not config.is_vivify_filetype(ft) then
    return
  end

  -- Get all lines from buffer
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local content = table.concat(lines, "\n")

  -- Get file path
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  if filepath == "" then
    debug_log("Buffer has no file path, skipping sync")
    return
  end

  -- Build URL matching vivify.vim format: /viewer + percent_encoded_path (NO slash between!)
  -- Example: http://localhost:31622/viewerC%3A/path/file.md
  -- The server's urlToPath() strips "/viewer" prefix and decodes, yielding the filepath
  local url = get_base_url() .. "/viewer" .. percent_encode_path(filepath)

  async_post(url, { content = content })
end

---Sync cursor position to Vivify viewer
---@param bufnr number|nil Buffer number (default: current)
function M.sync_cursor(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Check filetype dynamically (matching original behavior)
  local ft = vim.bo[bufnr].filetype
  if not config.is_vivify_filetype(ft) then
    return
  end

  -- Get cursor line (1-indexed)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]

  -- Get file path
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  if filepath == "" then
    debug_log("Buffer has no file path, skipping cursor sync")
    return
  end

  -- Build URL matching vivify.vim format (no slash between /viewer and path)
  local url = get_base_url() .. "/viewer" .. percent_encode_path(filepath)

  async_post(url, { cursor = line })
end

---Open current file in Vivify viewer
---@param bufnr number|nil Buffer number (default: current)
function M.open(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local filepath = vim.api.nvim_buf_get_name(bufnr)
  if filepath == "" then
    vim.notify("[vivify.nvim] Buffer has no file path", vim.log.levels.WARN)
    return
  end

  -- Get cursor line
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]

  -- Escape colons in filepath for viv command (as in original)
  -- Original: expand('%:p')->substitute(':', '\\:', 'g')
  local escaped_path = filepath:gsub(":", "\\:")

  -- Construct the argument: filepath:line
  local arg = string.format("%s:%d", escaped_path, line)

  -- Get the viv binary path (configured or default "viv")
  local viv_cmd = config.get_viv_binary()

  debug_log("Opening with viv (%s): %s", viv_cmd, arg)

  -- Cross-platform job execution
  if is_windows() then
    -- On Windows, use cmd /c with string command for maximum compatibility with .cmd files
    local cmd_str = string.format('cmd /c ""%s" "%s""', viv_cmd, arg)
    vim.fn.jobstart(cmd_str, {
      detach = true,
    })
  else
    -- Unix: standard array execution
    vim.fn.jobstart({ viv_cmd, arg }, {
      detach = true,
    })
  end
end

---Check if Vivify dependencies are available
---@return boolean ok
---@return string|nil error_message
function M.check_dependencies()
  -- Check for plenary.nvim
  if not has_plenary() then
    return false, "plenary.nvim not found. Please install nvim-lua/plenary.nvim"
  end

  -- Get the configured viv binary
  local viv_cmd = config.get_viv_binary()

  -- Check for viv executable
  if vim.fn.executable(viv_cmd) ~= 1 then
    if viv_cmd == "viv" then
      return false, "'viv' command not found in PATH. Please install Vivify: https://github.com/jannis-baum/Vivify"
    else
      return false, string.format("Custom viv binary not found: '%s'. Check your viv_binary config.", viv_cmd)
    end
  end

  return true, nil
end

return M

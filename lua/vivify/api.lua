---@class VivifyApi
---@field private _initialized boolean
local M = {}

local config = require("vivify.config")

-- Logger setup (lazy loaded)
---@type table|nil
local logger = nil

---Get or create the logger instance
---@return table Logger instance
local function get_logger()
  if logger then
    return logger
  end
  local ok, log = pcall(require, "plenary.log")
  if ok then
    logger = log.new({
      plugin = "vivify.nvim",
      level = config.options.debug and "debug" or "info",
      use_console = false, -- Don't spam console
      use_file = true, -- Log to file for debugging
    })
  else
    -- Fallback logger that does nothing
    logger = {
      debug = function() end,
      info = function() end,
      warn = function() end,
      error = function() end,
    }
  end
  return logger
end

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

---Percent-encode a filepath to match Vivify server's pathToURL() format.
---The server uses: encodeURIComponent(path).replaceAll('%2F', '/')
---
---CRITICAL for Windows: The browser URL is constructed by Node.js which uses
---backslashes for Windows paths. But Neovim on Windows uses forward slashes
---in buffer names. We must convert to backslashes to match the browser.
---
---@param str string Filepath to encode
---@return string URL-encoded path (matching server's pathToURL format)
local function encode_for_vivify(str)
  if not str then
    return ""
  end
  -- Get absolute, normalized path
  str = vim.fn.fnamemodify(str, ":p")

  -- CRITICAL: On Windows, convert forward slashes to backslashes
  -- This is because:
  -- 1. Neovim on Windows uses forward slashes in buffer names (e.g., c:/work/...)
  -- 2. The viv CLI uses Node.js path.resolve() which returns backslashes (e.g., C:\Work\...)
  -- 3. The browser registers the path with backslashes
  -- 4. We must match that exact format for the sync to work
  if is_windows() then
    str = str:gsub("/", "\\")
  end

  -- After converting slashes, encode all special characters
  -- On Windows, backslashes become %5C
  -- Colons become %3A
  -- Forward slashes are NOT encoded (only relevant on Unix)
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

---Log debug message (both to notify and file log)
---@param msg string Message to log
---@vararg any Additional format arguments
local function debug_log(msg, ...)
  local formatted = string.format(msg, ...)
  -- Always log to file for debugging
  get_logger().debug(formatted)

  if config.options.debug then
    vim.schedule(function()
      vim.notify("[vivify.nvim] " .. formatted, vim.log.levels.DEBUG)
    end)
  end
end

---Log error message
---@param msg string Message to log
---@vararg any Additional format arguments
local function error_log(msg, ...)
  local formatted = string.format(msg, ...)
  get_logger().error(formatted)
  if config.options.debug then
    vim.schedule(function()
      vim.notify("[vivify.nvim] ERROR: " .. formatted, vim.log.levels.ERROR)
    end)
  end
end

---Execute async HTTP POST request using plenary.curl
---This is the reliable cross-platform solution that works correctly
---@param url string Full URL
---@param data table Data to send as JSON
local function async_post(url, data)
  local json_data = vim.fn.json_encode(data)

  debug_log("POST %s (data size: %d bytes)", url, #json_data)

  -- Use plenary.curl for reliable async HTTP
  local ok, curl = pcall(require, "plenary.curl")
  if not ok then
    error_log("plenary.curl not available")
    return
  end

  -- Perform async POST request
  curl.post(url, {
    body = json_data,
    headers = {
      ["Content-Type"] = "application/json",
    },
    callback = function(response)
      if response.status and response.status >= 200 and response.status < 300 then
        debug_log("POST success (status %d, clients: %s)", response.status, response.body or "?")
      elseif response.status then
        debug_log("POST response status: %d", response.status)
      end
    end,
    on_error = function(err)
      -- Only log if debug mode to avoid spam when server isn't running
      debug_log("POST error: %s", vim.inspect(err))
    end,
  })
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

  -- Build URL matching Vivify server's pathToURL format: /viewer/ + encoded_path
  -- The server uses: `/${route}/${encodeURIComponent(path).replaceAll('%2F', '/')}`
  -- Example: http://localhost:31622/viewer/C%3A%5CUsers%5Cpath%5Cfile.md
  -- The server's urlToPath() strips "/viewer" prefix and decodes, yielding the filepath
  local url = get_base_url() .. "/viewer/" .. encode_for_vivify(filepath)

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

  -- Build URL matching Vivify server's pathToURL format (with slash after /viewer)
  local url = get_base_url() .. "/viewer/" .. encode_for_vivify(filepath)

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

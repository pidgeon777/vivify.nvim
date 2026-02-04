---@class VivifyApi
---@field private _initialized boolean
local M = {}

local config = require("vivify.config")

-- Logger setup (lazy loaded)
---@type table|nil
local logger = nil

-- Forward declarations (avoid diagnostics for use-before-definition)
---@type fun(msg: string, ...)|nil
local debug_log
---@type fun(msg: string, ...)|nil
local error_log

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
---CRITICAL for Windows: The browser URL is constructed by Node.js which uses:
---1. Backslashes for path separators (not forward slashes)
---2. The actual filesystem case (C:\Work\MEGA not c:\work\mega)
---
---Neovim on Windows may have:
---1. Forward slashes in buffer names (c:/work/...)
---2. Lowercase paths depending on how the file was opened
---
---We use fs_realpath to get the true filesystem path with correct case.
---
---@param str string Filepath to encode
---@return string URL-encoded path (matching server's pathToURL format)
local function encode_for_vivify(str)
  if not str then
    return ""
  end

  -- Get absolute, normalized path
  local normalized = vim.fn.fnamemodify(str, ":p")
  local realpath = normalized

  -- CRITICAL: On Windows, use fs_realpath to get the TRUE filesystem path
  -- This resolves:
  -- 1. Case differences (c:\work -> C:\Work as stored on disk)
  -- 2. Slash direction (returns backslashes on Windows)
  -- This matches exactly what Node.js path.resolve() returns
  if is_windows() then
    local uv = vim.uv or vim.loop
    local resolved = uv.fs_realpath(normalized)
    if resolved then
      realpath = resolved
    else
      -- Fallback: at least convert forward slashes to backslashes
      realpath = normalized:gsub("/", "\\")
    end
  end

  if config.options.debug then
    debug_log("Sync path raw=%s", str)
    debug_log("Sync path normalized=%s", normalized)
    debug_log("Sync path real=%s", realpath)
  end

  -- Encode all special characters except forward slash
  -- On Windows: backslashes become %5C, colons become %3A
  -- On Unix: forward slashes are preserved
  local encoded = realpath:gsub("([^%w%-%._~/])", function(c)
    return string.format("%%%02X", string.byte(c))
  end)

  if config.options.debug then
    debug_log("Sync path encoded=%s", encoded)
  end

  return encoded
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
debug_log = function(msg, ...)
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
error_log = function(msg, ...)
  local formatted = string.format(msg, ...)
  get_logger().error(formatted)
  if config.options.debug then
    vim.schedule(function()
      vim.notify("[vivify.nvim] ERROR: " .. formatted, vim.log.levels.ERROR)
    end)
  end
end

---Decode the number of connected clients from response body
---@param response table|nil
---@return number|nil
local function decode_clients(response)
  if not response or response.body == nil then
    return nil
  end

  if type(response.body) == "table" and response.body.clients ~= nil then
    return tonumber(response.body.clients)
  end

  if type(response.body) == "string" and response.body ~= "" then
    local json_decode = vim.json and vim.json.decode or vim.fn.json_decode
    local ok, decoded = pcall(json_decode, response.body)
    if ok and type(decoded) == "table" and decoded.clients ~= nil then
      return tonumber(decoded.clients)
    end
  end

  return nil
end

---Execute async HTTP POST request using plenary.curl
---This is the reliable cross-platform solution that works correctly
---@param url string Full URL
---@param data table Data to send as JSON
---@param opts? table Optional callbacks
---@param opts.on_response? fun(response: table): nil
---@param opts.on_error? fun(err: any): nil
local function async_post(url, data, opts)
  local json_data = vim.json.encode(data)

  debug_log("POST %s (data size: %d bytes)", url, #json_data)

  -- Use plenary.curl for reliable async HTTP
  local ok, curl = pcall(require, "plenary.curl")
  if not ok then
    error_log("plenary.curl not available")
    return
  end

  local on_response = opts and opts.on_response or nil
  local on_error = opts and opts.on_error or nil

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

      if on_response then
        on_response(response)
      end
    end,
    on_error = function(err)
      -- Only log if debug mode to avoid spam when server isn't running
      debug_log("POST error: %s", vim.inspect(err))
      if on_error then
        on_error(err)
      end
    end,
  })
end

---Build sync URL candidates (primary and fallback)
---@param filepath string
---@return string[]
local function build_sync_urls(filepath)
  local encoded = encode_for_vivify(filepath)
  local urls = {
    -- Primary: matches server pathToURL (with slash)
    get_base_url() .. "/viewer/" .. encoded,
    -- Fallback: original vivify.vim format (no slash)
    get_base_url() .. "/viewer" .. encoded,
  }

  if config.options.debug then
    debug_log("Sync URLs: %s | %s", urls[1], urls[2])
  end

  return urls
end

---POST with fallback if no clients are matched
---@param urls string[]
---@param data table
local function post_with_fallback(urls, data)
  local function try_at(index)
    local url = urls[index]
    if not url then
      return
    end

    async_post(url, data, {
      on_response = function(response)
        local clients = decode_clients(response)
        if clients == 0 and index < #urls then
          debug_log("No clients for %s, trying fallback %d/%d", url, index + 1, #urls)
          vim.schedule(function()
            try_at(index + 1)
          end)
        end
      end,
    })
  end

  try_at(1)
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

  local urls = build_sync_urls(filepath)
  post_with_fallback(urls, { content = content })
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

  local urls = build_sync_urls(filepath)
  post_with_fallback(urls, { cursor = line })
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

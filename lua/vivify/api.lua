---@class VivifyApi
---@field private _initialized boolean
local M = {}

local config = require("vivify.config")

---URL encode a string (percent encoding)
---@param str string String to encode
---@return string Encoded string
local function url_encode(str)
  if not str then
    return ""
  end
  -- Convert to string if needed
  str = tostring(str)
  -- Encode special characters
  str = str:gsub("([^%w%-%.%_%~])", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
  return str
end

---Normalize file path for URL usage
---@param path string File path
---@return string Normalized and encoded path
local function normalize_path_for_url(path)
  if not path then
    return ""
  end
  -- Normalize path separators to forward slashes
  path = path:gsub("\\", "/")
  -- URL encode the path
  -- But keep forward slashes and colons (for Windows drive letters)
  local parts = {}
  for part in path:gmatch("[^/]+") do
    table.insert(parts, url_encode(part))
  end
  local result = table.concat(parts, "/")
  -- Preserve leading slash if present
  if path:sub(1, 1) == "/" then
    result = "/" .. result
  end
  return result
end

---Get the base URL for Vivify server
---@return string Base URL
local function get_base_url()
  return string.format("http://localhost:%d", config.get_port())
end

---Log debug message
---@param msg string Message to log
---@vararg any Additional format arguments
local function debug_log(msg, ...)
  if config.options.debug then
    local formatted = string.format(msg, ...)
    vim.notify("[vivify.nvim] " .. formatted, vim.log.levels.DEBUG)
  end
end

---Execute async HTTP POST request
---@param url string Full URL
---@param data table Data to send as JSON
local function async_post(url, data)
  local json_data = vim.fn.json_encode(data)

  debug_log("POST %s with data: %s", url, json_data)

  -- Use vim.system for Neovim 0.10+ or fallback to jobstart
  if vim.system then
    vim.system({
      "curl",
      "-s", -- silent
      "-X", "POST",
      "-H", "Content-Type: application/json",
      "-d", json_data,
      url,
    }, {
      text = true,
      detach = true,
    }, function(obj)
      if obj.code ~= 0 and config.options.debug then
        vim.schedule(function()
          debug_log("curl failed with code %d: %s", obj.code, obj.stderr or "")
        end)
      end
    end)
  else
    -- Fallback for older Neovim versions
    vim.fn.jobstart({
      "curl",
      "-s",
      "-X", "POST",
      "-H", "Content-Type: application/json",
      "-d", json_data,
      url,
    }, {
      detach = true,
      on_stderr = function(_, data)
        if config.options.debug and data and data[1] ~= "" then
          vim.schedule(function()
            debug_log("curl error: %s", table.concat(data, "\n"))
          end)
        end
      end,
    })
  end
end

---Sync buffer content to Vivify viewer
---@param bufnr number|nil Buffer number (default: current)
function M.sync_content(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Get all lines from buffer
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local content = table.concat(lines, "\n")

  -- Get file path
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  if filepath == "" then
    debug_log("Buffer has no file path, skipping sync")
    return
  end

  local encoded_path = normalize_path_for_url(filepath)
  local url = get_base_url() .. "/viewer" .. encoded_path

  async_post(url, { content = content })
end

---Sync cursor position to Vivify viewer
---@param bufnr number|nil Buffer number (default: current)
function M.sync_cursor(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Get cursor line (1-indexed)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]

  -- Get file path
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  if filepath == "" then
    debug_log("Buffer has no file path, skipping cursor sync")
    return
  end

  local encoded_path = normalize_path_for_url(filepath)
  local url = get_base_url() .. "/viewer" .. encoded_path

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
  local escaped_path = filepath:gsub(":", "\\:")

  -- Construct the argument: filepath:line
  local arg = string.format("%s:%d", escaped_path, line)

  debug_log("Opening with viv: %s", arg)

  -- Use vim.system for Neovim 0.10+ or fallback
  if vim.system then
    vim.system({ "viv", arg }, {
      detach = true,
      text = true,
    }, function(obj)
      if obj.code ~= 0 then
        vim.schedule(function()
          vim.notify(
            string.format("[vivify.nvim] Failed to open viewer: %s", obj.stderr or "unknown error"),
            vim.log.levels.ERROR
          )
        end)
      end
    end)
  else
    vim.fn.jobstart({ "viv", arg }, {
      detach = true,
      on_stderr = function(_, data)
        if data and data[1] ~= "" then
          vim.schedule(function()
            vim.notify(
              string.format("[vivify.nvim] Failed to open viewer: %s", table.concat(data, "\n")),
              vim.log.levels.ERROR
            )
          end)
        end
      end,
    })
  end
end

---Check if Vivify dependencies are available
---@return boolean, string|nil ok, error_message
function M.check_dependencies()
  -- Check for viv executable
  if vim.fn.executable("viv") ~= 1 then
    return false, "'viv' command not found in PATH. Please install Vivify: https://github.com/jannis-baum/Vivify"
  end

  -- Check for curl
  if vim.fn.executable("curl") ~= 1 then
    return false, "'curl' command not found in PATH"
  end

  return true, nil
end

return M

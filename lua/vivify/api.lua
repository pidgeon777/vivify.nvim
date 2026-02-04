---@class VivifyApi
---@field private _initialized boolean
local M = {}

local config = require("vivify.config")

---URL percent encode a string (matching Python's urllib.parse.quote behavior)
---Python's quote() has safe='/' by default, so "/" is NOT encoded.
---All other special characters ARE encoded including ":" and "\" (Windows paths).
---@param str string String to encode
---@return string Encoded string
local function percent_encode(str)
  if not str then
    return ""
  end
  str = tostring(str)
  -- Normalize Windows backslashes to forward slashes for URL compatibility
  -- This ensures cross-platform URL consistency
  str = str:gsub("\\", "/")
  -- Encode everything except unreserved characters (RFC 3986) and "/"
  -- unreserved = ALPHA / DIGIT / "-" / "." / "_" / "~"
  -- "/" is kept as-is to match Python's urllib.parse.quote(safe='/') default
  str = str:gsub("([^%w%-%._~/])", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
  return str
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
    vim.schedule(function()
      vim.notify("[vivify.nvim] " .. formatted, vim.log.levels.DEBUG)
    end)
  end
end

---Execute async HTTP POST request using stdin for data (handles large files safely)
---@param url string Full URL
---@param data table Data to send as JSON
local function async_post(url, data)
  local json_data = vim.fn.json_encode(data)

  debug_log("POST %s (data size: %d bytes)", url, #json_data)

  -- Use vim.system for Neovim 0.10+ or fallback to jobstart
  if vim.system then
    -- Use stdin for data to avoid command line length limits
    vim.system({
      "curl",
      "-s", -- silent
      "-X", "POST",
      "-H", "Content-Type: application/json",
      "--data", "@-", -- read from stdin
      url,
    }, {
      text = true,
      stdin = json_data, -- send data via stdin
      -- Note: NOT using detach=true so callback works for error handling
    }, function(obj)
      if obj.code ~= 0 and config.options.debug then
        vim.schedule(function()
          debug_log("curl failed with code %d: %s", obj.code, obj.stderr or "")
        end)
      end
    end)
  else
    -- Fallback for older Neovim versions using jobstart with stdin
    local job_id = vim.fn.jobstart({
      "curl",
      "-s",
      "-X", "POST",
      "-H", "Content-Type: application/json",
      "--data", "@-", -- read from stdin
      url,
    }, {
      on_stderr = function(_, data_lines)
        if config.options.debug and data_lines and data_lines[1] ~= "" then
          vim.schedule(function()
            debug_log("curl error: %s", table.concat(data_lines, "\n"))
          end)
        end
      end,
    })

    if job_id > 0 then
      -- Send data via stdin and close
      vim.fn.chansend(job_id, json_data)
      vim.fn.chanclose(job_id, "stdin")
    end
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

  -- Percent encode the full path (matching original behavior)
  -- Original: s:viv_url . '/viewer' . s:percent_encode(expand('%:p'))
  local encoded_path = percent_encode(filepath)
  local url = get_base_url() .. "/viewer" .. encoded_path

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

  -- Percent encode the full path (matching original behavior)
  local encoded_path = percent_encode(filepath)
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
  -- Original: expand('%:p')->substitute(':', '\\:', 'g')
  local escaped_path = filepath:gsub(":", "\\:")

  -- Construct the argument: filepath:line
  local arg = string.format("%s:%d", escaped_path, line)

  -- Get the viv binary path (configured or default "viv")
  local viv_cmd = config.get_viv_binary()

  debug_log("Opening with viv (%s): %s", viv_cmd, arg)

  -- Use vim.system for Neovim 0.10+ or fallback
  if vim.system then
    vim.system({ viv_cmd, arg }, {
      text = true,
      -- Detach so viv runs independently (matching original behavior)
      detach = true,
      -- Redirect IO to null (matching original: 'in_io': 'null', 'out_io': 'null', 'err_io': 'null')
      stdin = false,
      stdout = false,
      stderr = false,
    })
  else
    vim.fn.jobstart({ viv_cmd, arg }, {
      detach = true,
      on_stdout = false,
      on_stderr = false,
    })
  end
end

---Check if Vivify dependencies are available
---@return boolean ok
---@return string|nil error_message
function M.check_dependencies()
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

  -- Check for curl
  if vim.fn.executable("curl") ~= 1 then
    return false, "'curl' command not found in PATH"
  end

  return true, nil
end

return M

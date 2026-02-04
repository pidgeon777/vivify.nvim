---@class VivifyConfig
---@field port number|nil Port for Vivify server (default: 31622 or $VIV_PORT)
---@field instant_refresh boolean Refresh on TextChanged (true) or CursorHold (false)
---@field auto_scroll boolean Enable auto-scroll on cursor movement
---@field filetypes string[] Filetypes to treat as markdown
---@field debug boolean Enable debug logging

---@type VivifyConfig
local defaults = {
  port = nil, -- Will use $VIV_PORT or 31622
  instant_refresh = true,
  auto_scroll = true,
  filetypes = { "markdown", "md" },
  debug = false,
}

local M = {}

---@type VivifyConfig
M.options = vim.deepcopy(defaults)

---Get the configured port for Vivify server
---@return number
function M.get_port()
  if M.options.port then
    return M.options.port
  end
  local env_port = vim.env.VIV_PORT
  if env_port and env_port ~= "" then
    local port = tonumber(env_port)
    if port then
      return port
    end
  end
  return 31622
end

---Check if a filetype should be treated as markdown
---@param ft string Filetype to check
---@return boolean
function M.is_vivify_filetype(ft)
  if not ft or ft == "" then
    return false
  end
  for _, pattern in ipairs(M.options.filetypes) do
    if ft:match(pattern) then
      return true
    end
  end
  return false
end

---Validate configuration options
---@param opts table|nil User options
---@return VivifyConfig
function M.validate(opts)
  opts = opts or {}

  vim.validate({
    port = { opts.port, { "number", "nil" }, true },
    instant_refresh = { opts.instant_refresh, "boolean", true },
    auto_scroll = { opts.auto_scroll, "boolean", true },
    filetypes = { opts.filetypes, "table", true },
    debug = { opts.debug, "boolean", true },
  })

  return vim.tbl_deep_extend("force", defaults, opts)
end

---Setup configuration
---@param opts table|nil User options
function M.setup(opts)
  M.options = M.validate(opts)
end

---Reset configuration to defaults
function M.reset()
  M.options = vim.deepcopy(defaults)
end

return M

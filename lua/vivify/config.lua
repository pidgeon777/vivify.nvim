---@class VivifyConfig
---@field port number|nil Port for Vivify server (default: 31622 or $VIV_PORT)
---@field viv_binary string|nil Custom path to viv executable (default: "viv" from PATH)
---@field instant_refresh boolean Refresh on TextChanged (true) or CursorHold (false)
---@field auto_scroll boolean Enable auto-scroll on cursor movement
---@field filetypes string[] Filetypes to treat as markdown
---@field debug boolean Enable debug logging

---@type VivifyConfig
local defaults = {
  port = nil, -- Will use $VIV_PORT or 31622
  viv_binary = nil, -- Will use "viv" from PATH
  instant_refresh = true,
  auto_scroll = true,
  filetypes = { "markdown", "md" },
  debug = false,
}

local M = {}

---@type VivifyConfig
M.options = vim.deepcopy(defaults)

---Read legacy g: variables from original vivify.vim for backwards compatibility
---@return table Legacy options merged as modern config format
local function read_legacy_globals()
  local legacy = {}

  -- g:vivify_instant_refresh (1 = true, 0 = false)
  local instant = vim.g.vivify_instant_refresh
  if instant ~= nil then
    legacy.instant_refresh = (instant == 1 or instant == true)
  end

  -- g:vivify_auto_scroll (1 = true, 0 = false)
  local scroll = vim.g.vivify_auto_scroll
  if scroll ~= nil then
    legacy.auto_scroll = (scroll == 1 or scroll == true)
  end

  -- g:vivify_filetypes (array of additional filetypes)
  local filetypes = vim.g.vivify_filetypes
  if filetypes and type(filetypes) == "table" then
    -- Merge with defaults: add user filetypes to the default list
    local merged = vim.deepcopy(defaults.filetypes)
    for _, ft in ipairs(filetypes) do
      if not vim.tbl_contains(merged, ft) then
        table.insert(merged, ft)
      end
    end
    legacy.filetypes = merged
  end

  return legacy
end

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

---Get the viv binary path/command to use
---@return string The viv command or full path
function M.get_viv_binary()
  if M.options.viv_binary and M.options.viv_binary ~= "" then
    return M.options.viv_binary
  end
  return "viv"
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
    viv_binary = { opts.viv_binary, { "string", "nil" }, true },
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
  -- Read legacy g: variables first (for backwards compatibility with vivify.vim)
  local legacy = read_legacy_globals()
  -- Merge: defaults < legacy globals < user opts (user opts have highest priority)
  local merged = vim.tbl_deep_extend("force", defaults, legacy, opts or {})
  M.options = M.validate(merged)
end

---Reset configuration to defaults
function M.reset()
  M.options = vim.deepcopy(defaults)
end

return M

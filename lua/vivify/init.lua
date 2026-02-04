---vivify.nvim - Neovim plugin for Vivify markdown preview
---@class Vivify
---@field config VivifyConfig
---@field api VivifyApi
---@field autocmds VivifyAutocmds
---@field setup fun(opts?: VivifySetupOptions): nil
local M = {}

---@class VivifySetupOptions
---@field port? number Port for Vivify server (default: 31622 or $VIV_PORT)
---@field instant_refresh? boolean Refresh on TextChanged (true) or CursorHold (false)
---@field auto_scroll? boolean Enable auto-scroll on cursor movement
---@field filetypes? string[] Filetypes to treat as markdown
---@field debug? boolean Enable debug logging

local PLUGIN_NAME = "vivify.nvim"
local MINIMUM_NVIM_VERSION = { major = 0, minor = 9, patch = 0 }

---@type boolean
local initialized = false

---Check if current Neovim version meets minimum requirements
---@return boolean
local function check_nvim_version()
  local v = vim.version()
  if v.major > MINIMUM_NVIM_VERSION.major then
    return true
  elseif v.major == MINIMUM_NVIM_VERSION.major then
    if v.minor > MINIMUM_NVIM_VERSION.minor then
      return true
    elseif v.minor == MINIMUM_NVIM_VERSION.minor then
      return v.patch >= MINIMUM_NVIM_VERSION.patch
    end
  end
  return false
end

---Setup the plugin
---@param opts? VivifySetupOptions Configuration options
function M.setup(opts)
  if initialized then
    return
  end

  -- Check Neovim version
  if not check_nvim_version() then
    local min_ver = string.format(
      "%d.%d.%d",
      MINIMUM_NVIM_VERSION.major,
      MINIMUM_NVIM_VERSION.minor,
      MINIMUM_NVIM_VERSION.patch
    )
    vim.notify(
      string.format("[%s] Requires Neovim %s or later", PLUGIN_NAME, min_ver),
      vim.log.levels.ERROR
    )
    return
  end

  -- Setup configuration
  local config = require("vivify.config")
  config.setup(opts)

  -- Setup commands
  local commands = require("vivify.commands")
  commands.setup()

  -- Setup autocmds
  local autocmds = require("vivify.autocmds")
  autocmds.setup()

  initialized = true
end

---Open current buffer in Vivify viewer
---@param bufnr? number Buffer number (default: current)
function M.open(bufnr)
  local api = require("vivify.api")
  api.open(bufnr)
end

---Sync buffer content to viewer
---@param bufnr? number Buffer number (default: current)
function M.sync_content(bufnr)
  local api = require("vivify.api")
  api.sync_content(bufnr)
end

---Sync cursor position to viewer
---@param bufnr? number Buffer number (default: current)
function M.sync_cursor(bufnr)
  local api = require("vivify.api")
  api.sync_cursor(bufnr)
end

---Enable auto-sync
function M.enable()
  local autocmds = require("vivify.autocmds")
  autocmds.setup()
end

---Disable auto-sync
function M.disable()
  local autocmds = require("vivify.autocmds")
  autocmds.disable()
end

---Toggle auto-sync
---@return boolean New state (true = enabled)
function M.toggle()
  local autocmds = require("vivify.autocmds")
  return autocmds.toggle()
end

---Check if auto-sync is active
---@return boolean
function M.is_active()
  local autocmds = require("vivify.autocmds")
  return autocmds.is_active()
end

---Get plugin configuration
---@return VivifyConfig
function M.get_config()
  local config = require("vivify.config")
  return config.options
end

---Check if dependencies are available
---@return boolean ok
---@return string|nil error_message
function M.check_dependencies()
  local api = require("vivify.api")
  return api.check_dependencies()
end

return M

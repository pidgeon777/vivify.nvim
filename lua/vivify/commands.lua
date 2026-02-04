---@class VivifyCommands
local M = {}

local api = require("vivify.api")
local autocmds = require("vivify.autocmds")

---Setup user commands
function M.setup()
  -- Main command to open in Vivify viewer
  vim.api.nvim_create_user_command("Vivify", function()
    api.open()
  end, {
    desc = "Open current file in Vivify markdown viewer",
  })

  -- Command to manually sync content
  vim.api.nvim_create_user_command("VivifySync", function()
    api.sync_content()
    vim.notify("[vivify.nvim] Content synced", vim.log.levels.INFO)
  end, {
    desc = "Manually sync buffer content to Vivify viewer",
  })

  -- Command to toggle auto-sync
  vim.api.nvim_create_user_command("VivifyToggle", function()
    local enabled = autocmds.toggle()
    if enabled then
      vim.notify("[vivify.nvim] Auto-sync enabled", vim.log.levels.INFO)
    else
      vim.notify("[vivify.nvim] Auto-sync disabled", vim.log.levels.INFO)
    end
  end, {
    desc = "Toggle Vivify auto-sync on/off",
  })

  -- Command to stop syncing
  vim.api.nvim_create_user_command("VivifyStop", function()
    autocmds.disable()
    vim.notify("[vivify.nvim] Syncing stopped", vim.log.levels.INFO)
  end, {
    desc = "Stop Vivify auto-sync",
  })

  -- Command to start syncing
  vim.api.nvim_create_user_command("VivifyStart", function()
    autocmds.setup()
    vim.notify("[vivify.nvim] Syncing started", vim.log.levels.INFO)
  end, {
    desc = "Start Vivify auto-sync",
  })

  -- Command to check status
  vim.api.nvim_create_user_command("VivifyStatus", function()
    local status = autocmds.is_active() and "active" or "inactive"
    local config = require("vivify.config")
    local lines = {
      "vivify.nvim status:",
      string.format("  Auto-sync: %s", status),
      string.format("  Port: %d", config.get_port()),
      string.format("  Instant refresh: %s", config.options.instant_refresh and "yes" or "no"),
      string.format("  Auto-scroll: %s", config.options.auto_scroll and "yes" or "no"),
      string.format("  Filetypes: %s", table.concat(config.options.filetypes, ", ")),
    }
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
  end, {
    desc = "Show Vivify status",
  })
end

return M

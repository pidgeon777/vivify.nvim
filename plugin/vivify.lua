-- vivify.nvim - Plugin entry point
-- Connects Neovim to Vivify markdown preview tool
-- https://github.com/pidgeon777/vivify.nvim

-- Prevent double loading
if vim.g.loaded_vivify_nvim then
  return
end
vim.g.loaded_vivify_nvim = true

-- Check minimum Neovim version
if vim.fn.has("nvim-0.9.0") ~= 1 then
  vim.api.nvim_err_writeln("[vivify.nvim] Requires Neovim 0.9.0 or later")
  return
end

-- Create preliminary :Vivify command for lazy loading
-- This allows the plugin to work even without explicit setup() call
-- When setup() is called, commands.setup() will redefine all commands properly
vim.api.nvim_create_user_command("Vivify", function()
  -- Ensure plugin is initialized with defaults if setup() wasn't called
  local vivify = require("vivify")
  -- Check if already initialized by checking if autocmds were set up
  -- or if this is the first time
  local config = require("vivify.config")
  local commands = require("vivify.commands")
  local autocmds = require("vivify.autocmds")

  -- Setup if not already done (first-time lazy load scenario)
  if not autocmds.is_active() then
    config.setup({})
    commands.setup()
    autocmds.setup()
  end

  vivify.open()
end, {
  desc = "Open current file in Vivify markdown viewer",
})

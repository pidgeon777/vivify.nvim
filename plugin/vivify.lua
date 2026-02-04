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

-- Create the :Vivify command for lazy loading
-- This allows the plugin to work even without explicit setup()
vim.api.nvim_create_user_command("Vivify", function()
  -- Ensure plugin is initialized
  local vivify = require("vivify")
  if not vivify.is_active() then
    vivify.setup()
  end
  vivify.open()
end, {
  desc = "Open current file in Vivify markdown viewer",
})

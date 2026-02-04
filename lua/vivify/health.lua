---@class VivifyHealth
---Health check module for :checkhealth vivify
local M = {}

---Run health check
function M.check()
  vim.health.start("vivify.nvim")

  -- Check Neovim version
  local nvim_version = vim.version()
  local version_str = string.format("%d.%d.%d", nvim_version.major, nvim_version.minor, nvim_version.patch)

  if nvim_version.major == 0 and nvim_version.minor < 9 then
    vim.health.error(
      string.format("Neovim version %s is too old", version_str),
      { "Upgrade to Neovim 0.9.0 or later" }
    )
  else
    vim.health.ok(string.format("Neovim version: %s", version_str))
  end

  -- Check vim.system availability (0.10+)
  if vim.system then
    vim.health.ok("vim.system() available (Neovim 0.10+)")
  else
    vim.health.warn("vim.system() not available", { "Using vim.fn.jobstart() fallback", "Upgrade to Neovim 0.10+ for better async support" })
  end

  -- Check for viv executable (respect custom path)
  local viv_cmd = "viv"
  local config_loaded, config = pcall(require, "vivify.config")
  if config_loaded and config.get_viv_binary then
    viv_cmd = config.get_viv_binary()
  end

  local is_custom_path = viv_cmd ~= "viv"
  if is_custom_path then
    vim.health.info(string.format("Using custom viv binary: %s", viv_cmd))
  end

  if vim.fn.executable(viv_cmd) == 1 then
    vim.health.ok(string.format("'%s' command found", viv_cmd))

    -- Try to get version
    local result = vim.fn.system(string.format('"%s" --version 2>&1', viv_cmd))
    if vim.v.shell_error == 0 and result and result ~= "" then
      vim.health.info(string.format("viv version: %s", vim.trim(result)))
    end
  else
    if is_custom_path then
      vim.health.error(string.format("Custom viv binary not found: '%s'", viv_cmd), {
        "Check that the path is correct in your viv_binary config",
        "Make sure the file exists and is executable",
      })
    else
      vim.health.error("'viv' command not found in PATH", {
        "Install Vivify from: https://github.com/jannis-baum/Vivify",
        "Make sure the 'viv' binary is in your PATH",
        "Or set a custom path with: viv_binary = '/path/to/viv'",
      })
    end
  end

  -- Check for curl
  if vim.fn.executable("curl") == 1 then
    vim.health.ok("'curl' command found in PATH")
  else
    vim.health.error("'curl' command not found in PATH", {
      "Install curl for your operating system",
      "Windows: winget install curl.curl",
      "macOS: brew install curl",
      "Linux: Use your package manager (apt, yum, pacman, etc.)",
    })
  end

  -- Check configuration
  local cfg_ok, cfg = pcall(require, "vivify.config")
  if cfg_ok then
    vim.health.ok("Configuration loaded successfully")
    vim.health.info(string.format("Port: %d", cfg.get_port()))
    vim.health.info(string.format("viv binary: %s", cfg.get_viv_binary()))
    vim.health.info(string.format("Instant refresh: %s", cfg.options.instant_refresh and "enabled" or "disabled"))
    vim.health.info(string.format("Auto-scroll: %s", cfg.options.auto_scroll and "enabled" or "disabled"))
    vim.health.info(string.format("Filetypes: %s", table.concat(cfg.options.filetypes, ", ")))
  else
    vim.health.error("Failed to load configuration", { tostring(cfg) })
  end

  -- Check if Vivify server is reachable (optional)
  local port = cfg_ok and cfg.get_port() or 31622
  local curl_check = vim.fn.system(string.format("curl -s -o /dev/null -w '%%{http_code}' http://localhost:%d/ 2>&1", port))
  if curl_check and curl_check:match("^%d+$") then
    local code = tonumber(curl_check)
    if code and code >= 200 and code < 500 then
      vim.health.ok(string.format("Vivify server responding on port %d", port))
    else
      vim.health.warn(string.format("Vivify server not responding on port %d", port), {
        "Start Vivify by running 'viv' on a markdown file",
        "Or check if VIV_PORT environment variable is set correctly",
      })
    end
  else
    vim.health.warn("Could not check Vivify server status", {
      "Start Vivify by running 'viv' on a markdown file",
    })
  end
end

return M

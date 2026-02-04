# vivify.nvim

A modern Lua port of [vivify.vim](https://github.com/jannis-baum/vivify.vim) - connects Neovim to the [Vivify](https://github.com/jannis-baum/Vivify) live markdown preview tool.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/jannis-baum/assets/refs/heads/main/Vivify/showcase-dark.gif">
  <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/jannis-baum/assets/refs/heads/main/Vivify/showcase-light.gif">
  <img alt="Showcase" src="https://raw.githubusercontent.com/jannis-baum/assets/refs/heads/main/Vivify/showcase-dark.gif">
</picture>

## ✨ Features

- 📄 Open the current buffer's contents in Vivify with `:Vivify`
- 🔄 All open viewers automatically update their content as you edit
- 📍 All open viewers automatically scroll to keep in sync with your cursor
- 🏥 Health check support (`:checkhealth vivify`)
- 🔧 Modern Lua API with full type annotations
- 🖥️ Cross-platform support (Windows, macOS, Linux)

## 📋 Requirements

- **Neovim** 0.9.0 or later (0.10+ recommended for `vim.system()`)
- **[Vivify](https://github.com/jannis-baum/Vivify)** installed with `viv` command in PATH
- **curl** command available

## 📦 Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "pidgeon777/vivify.nvim",
  cmd = { "Vivify", "VivifyToggle", "VivifyStatus" },
  ft = { "markdown" },
  keys = {
    { "<leader>mv", "<cmd>Vivify<cr>", ft = "markdown", desc = "Open Vivify" },
  },
  opts = {
    -- your configuration here
  },
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "pidgeon777/vivify.nvim",
  config = function()
    require("vivify").setup()
  end,
}
```

### Manual

Clone this repository to your Neovim packages directory:

```bash
git clone https://github.com/pidgeon777/vivify.nvim \
  ~/.local/share/nvim/site/pack/plugins/start/vivify.nvim
```

## ⚙️ Configuration

```lua
require("vivify").setup({
  -- Port for Vivify server (uses $VIV_PORT or 31622 if not set)
  port = nil,

  -- Refresh content on TextChanged (true) or CursorHold (false)
  instant_refresh = true,

  -- Enable auto-scroll on cursor movement
  auto_scroll = true,

  -- Filetypes to treat as markdown
  filetypes = { "markdown", "md" },

  -- Enable debug logging
  debug = false,
})
```

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `port` | `number\|nil` | `nil` | Port for Vivify server. Uses `$VIV_PORT` env var or `31622` |
| `instant_refresh` | `boolean` | `true` | Sync on every text change vs. on cursor hold |
| `auto_scroll` | `boolean` | `true` | Scroll viewer with cursor movement |
| `filetypes` | `string[]` | `{"markdown", "md"}` | Filetypes to treat as markdown |
| `debug` | `boolean` | `false` | Enable debug logging |

## 🚀 Usage

### Commands

| Command | Description |
|---------|-------------|
| `:Vivify` | Open current buffer in Vivify viewer |
| `:VivifySync` | Manually sync buffer content |
| `:VivifyToggle` | Toggle auto-sync on/off |
| `:VivifyStart` | Enable auto-sync |
| `:VivifyStop` | Disable auto-sync |
| `:VivifyStatus` | Show plugin status |

### Keybindings

Add a keybinding in your config:

```lua
vim.keymap.set("n", "<leader>mv", "<cmd>Vivify<cr>", { desc = "Open Vivify" })
```

Or for markdown files only (using lazy.nvim):

```lua
{
  "pidgeon777/vivify.nvim",
  keys = {
    { "<leader>mv", "<cmd>Vivify<cr>", ft = "markdown", desc = "Open Vivify" },
  },
}
```

## 🔧 Lua API

```lua
local vivify = require("vivify")

-- Setup with options
vivify.setup(opts)

-- Open current buffer in Vivify
vivify.open()
vivify.open(bufnr)  -- specific buffer

-- Sync content/cursor manually
vivify.sync_content()
vivify.sync_cursor()

-- Enable/disable/toggle auto-sync
vivify.enable()
vivify.disable()
local enabled = vivify.toggle()

-- Check status
local is_active = vivify.is_active()
local config = vivify.get_config()

-- Check dependencies
local ok, error = vivify.check_dependencies()
```

## 🏥 Health Check

Run `:checkhealth vivify` to verify your installation:

```
vivify.nvim
- OK Neovim version: 0.10.0
- OK vim.system() available (Neovim 0.10+)
- OK 'viv' command found in PATH
- OK 'curl' command found in PATH
- OK Configuration loaded successfully
```

## 🔄 Migration from vivify.vim

If you're migrating from the original Vimscript plugin:

| vivify.vim | vivify.nvim |
|------------|-------------|
| `g:vivify_instant_refresh` | `opts.instant_refresh` |
| `g:vivify_auto_scroll` | `opts.auto_scroll` |
| `g:vivify_filetypes` | `opts.filetypes` |
| `:Vivify` | `:Vivify` (same) |

```lua
-- Before (vivify.vim)
vim.g.vivify_instant_refresh = 1
vim.g.vivify_auto_scroll = 1
vim.g.vivify_filetypes = { "vimwiki" }

-- After (vivify.nvim)
require("vivify").setup({
  instant_refresh = true,
  auto_scroll = true,
  filetypes = { "markdown", "md", "vimwiki" },
})
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

## 📄 License

MIT License - see [LICENSE](LICENSE) for details.

## 🙏 Credits

- [vivify.vim](https://github.com/jannis-baum/vivify.vim) - Original Vimscript plugin
- [Vivify](https://github.com/jannis-baum/Vivify) - The markdown preview tool

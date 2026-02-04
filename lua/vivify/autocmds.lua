---@class VivifyAutocmds
local M = {}

local config = require("vivify.config")
local api = require("vivify.api")

local AUGROUP_NAME = "Vivify"

---@type number|nil
local augroup_id = nil

---Check if autocmds are active
---@return boolean
function M.is_active()
  return augroup_id ~= nil
end

---Setup global autocmds (matching original vivify.vim behavior)
---Original uses global autocmds with dynamic config checking on each trigger
function M.setup()
  -- Create augroup (clear if exists)
  augroup_id = vim.api.nvim_create_augroup(AUGROUP_NAME, { clear = true })

  -- Content sync on TextChanged (instant refresh mode)
  -- Original: autocmd TextChanged,TextChangedI *
  --             \ if get(g:, "vivify_instant_refresh", 1) && s:is_vivify_filetype(&filetype) |
  --             \     call vivify#sync_content() |
  --             \ endif
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = augroup_id,
    pattern = "*",
    callback = function(args)
      -- Check config dynamically on each trigger (matching original)
      if config.options.instant_refresh and config.is_vivify_filetype(vim.bo[args.buf].filetype) then
        api.sync_content(args.buf)
      end
    end,
    desc = "Vivify: sync content on text change (instant mode)",
  })

  -- Content sync on CursorHold (non-instant refresh mode)
  -- Original: autocmd CursorHold,CursorHoldI *
  --             \ if !get(g:, "vivify_instant_refresh", 1) && s:is_vivify_filetype(&filetype) |
  --             \     call vivify#sync_content() |
  --             \ endif
  vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
    group = augroup_id,
    pattern = "*",
    callback = function(args)
      -- Check config dynamically on each trigger (matching original)
      if not config.options.instant_refresh and config.is_vivify_filetype(vim.bo[args.buf].filetype) then
        api.sync_content(args.buf)
      end
    end,
    desc = "Vivify: sync content on cursor hold",
  })

  -- Cursor sync on CursorMoved
  -- Original: autocmd CursorMoved,CursorMovedI *
  --             \ if get(g:, "vivify_auto_scroll", 1) && s:is_vivify_filetype(&filetype) |
  --             \     call vivify#sync_cursor() |
  --             \ endif
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = augroup_id,
    pattern = "*",
    callback = function(args)
      -- Check config dynamically on each trigger (matching original)
      if config.options.auto_scroll and config.is_vivify_filetype(vim.bo[args.buf].filetype) then
        api.sync_cursor(args.buf)
      end
    end,
    desc = "Vivify: sync cursor position",
  })
end

---Disable all autocmds
function M.disable()
  if augroup_id then
    vim.api.nvim_del_augroup_by_id(augroup_id)
    augroup_id = nil
  end
end

---Toggle autocmds on/off
---@return boolean New state (true = enabled)
function M.toggle()
  if M.is_active() then
    M.disable()
    return false
  else
    M.setup()
    return true
  end
end

return M

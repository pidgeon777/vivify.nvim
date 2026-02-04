---@class VivifyAutocmds
local M = {}

local config = require("vivify.config")
local api = require("vivify.api")

local AUGROUP_NAME = "Vivify"

---@type number|nil
local augroup_id = nil

---@type table<number, boolean>
local initialized_buffers = {}

---Check if autocmds are active
---@return boolean
function M.is_active()
  return augroup_id ~= nil
end

---Setup autocmds for a specific buffer
---@param bufnr number Buffer number
local function setup_buffer_autocmds(bufnr)
  if initialized_buffers[bufnr] then
    return
  end

  local ft = vim.bo[bufnr].filetype
  if not config.is_vivify_filetype(ft) then
    return
  end

  initialized_buffers[bufnr] = true

  -- Content sync autocmds
  if config.options.instant_refresh then
    -- Refresh on text change
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
      group = augroup_id,
      buffer = bufnr,
      callback = function()
        api.sync_content(bufnr)
      end,
      desc = "Vivify: sync content on text change",
    })
  else
    -- Refresh on cursor hold
    vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
      group = augroup_id,
      buffer = bufnr,
      callback = function()
        api.sync_content(bufnr)
      end,
      desc = "Vivify: sync content on cursor hold",
    })
  end

  -- Cursor sync autocmds
  if config.options.auto_scroll then
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
      group = augroup_id,
      buffer = bufnr,
      callback = function()
        api.sync_cursor(bufnr)
      end,
      desc = "Vivify: sync cursor position",
    })
  end
end

---Setup global autocmds
function M.setup()
  -- Create augroup (clear if exists)
  augroup_id = vim.api.nvim_create_augroup(AUGROUP_NAME, { clear = true })

  -- Watch for filetype changes and buffer enters
  vim.api.nvim_create_autocmd({ "BufEnter", "FileType" }, {
    group = augroup_id,
    pattern = "*",
    callback = function(args)
      setup_buffer_autocmds(args.buf)
    end,
    desc = "Vivify: initialize buffer on enter/filetype",
  })

  -- Clean up when buffer is deleted
  vim.api.nvim_create_autocmd("BufDelete", {
    group = augroup_id,
    pattern = "*",
    callback = function(args)
      initialized_buffers[args.buf] = nil
    end,
    desc = "Vivify: cleanup buffer tracking",
  })

  -- Initialize current buffer if applicable
  local current_buf = vim.api.nvim_get_current_buf()
  setup_buffer_autocmds(current_buf)
end

---Disable all autocmds
function M.disable()
  if augroup_id then
    vim.api.nvim_del_augroup_by_id(augroup_id)
    augroup_id = nil
  end
  initialized_buffers = {}
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

---Reinitialize buffer (useful after config change)
---@param bufnr number|nil Buffer number (default: current)
function M.reinit_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  initialized_buffers[bufnr] = nil
  setup_buffer_autocmds(bufnr)
end

return M

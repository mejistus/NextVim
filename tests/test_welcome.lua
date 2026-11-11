#!/usr/bin/env -S nvim --headless -u NONE -l
-- Run: nvim --headless -u NONE -l tests/test_welcome.lua

local script_dir = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local root = script_dir .. "../"
package.path = root .. "lua/?.lua;" .. root .. "lua/?/init.lua;" .. package.path

local welcome = require("configs.welcome")

-- The welcome screen is only shown when a UI is attached. Pretend one is.
vim.api.nvim_list_uis = function()
  return { { width = 80, height = 24 } }
end

local pass_count = 0
local fail_count = 0

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    pass_count = pass_count + 1
    io.write("  PASS: " .. name .. "\n")
  else
    fail_count = fail_count + 1
    io.write("  FAIL: " .. name .. " -- " .. tostring(err) .. "\n")
  end
end

local function eq(got, expected, label)
  if got ~= expected then
    error(string.format("%s: got %s, expected %s", label or "value", vim.inspect(got), vim.inspect(expected)), 2)
  end
end

test("welcome removes the empty startup buffer", function()
  local startup_buf = vim.api.nvim_get_current_buf()
  welcome.open()

  eq(vim.api.nvim_buf_is_valid(startup_buf), false, "startup buffer still valid")
  eq(#vim.api.nvim_list_bufs(), 1, "buffer count")
  eq(vim.bo[vim.api.nvim_get_current_buf()].filetype, "nextvim-welcome", "welcome buffer filetype")
end)

test("opening a file later leaves only that file", function()
  local path = vim.fn.tempname() .. ".txt"
  vim.fn.writefile({ "hello" }, path)

  -- Same buffer transition as selecting a file in Telescope or receiving a
  -- macOS "Open With" event after Neovide has already started.
  vim.cmd.edit(vim.fn.fnameescape(path))

  local bufs = vim.api.nvim_list_bufs()
  eq(#bufs, 1, "buffer count")
  eq(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufs[1]), ":t"), vim.fn.fnamemodify(path, ":t"), "remaining buffer")
end)

io.write(string.format("\n%d passed, %d failed\n", pass_count, fail_count))
if fail_count > 0 then
  os.exit(1)
end
os.exit(0)

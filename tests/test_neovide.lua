#!/usr/bin/env -S nvim --headless -u NONE -l
-- Run: nvim --headless -u NONE -l tests/test_neovide.lua

local script_dir = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local root = script_dir .. "../"
package.path = root .. "lua/?.lua;" .. root .. "lua/?/init.lua;" .. package.path

local neovide = require("core.neovide")

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

local saved = {
  neovide = vim.g.neovide,
  path = vim.env.PATH,
  lang = vim.env.LANG,
  lc_ctype = vim.env.LC_CTYPE,
  gui_path = vim.env.NEXT_VIM_GUI_PATH,
  shell = vim.o.shell,
  guifont = vim.o.guifont,
  guifontwide = vim.o.guifontwide,
  linespace = vim.o.linespace,
}

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp .. "/bin1", "p")
vim.fn.mkdir(tmp .. "/bin2", "p")

test("terminal Neovim is a no-op", function()
  vim.g.neovide = nil
  local before = vim.env.PATH
  neovide.setup_env()
  neovide.setup_ui()
  neovide.setup_keys()
  eq(vim.env.PATH, before, "PATH")
  eq(vim.fn.maparg("<D-s>", "n"), "", "Cmd-S")
end)

test("GUI PATH is prepended and deduplicated", function()
  vim.g.neovide = true
  vim.env.PATH = tmp .. "/bin2:/usr/bin"
  vim.env.NEXT_VIM_GUI_PATH = tmp .. "/bin1:" .. tmp .. "/bin2"
  neovide.setup_env()

  local parts = vim.split(vim.env.PATH, ":", { plain = true })
  eq(parts[1], tmp .. "/bin1", "custom path first")

  local count = 0
  for _, dir in ipairs(parts) do
    if dir == tmp .. "/bin2" then
      count = count + 1
    end
  end
  eq(count, 1, "duplicate bin2 entries")
  eq(vim.tbl_contains(parts, "/usr/bin"), true, "existing PATH kept")
end)

test("GUI options and Cmd maps are installed", function()
  vim.g.neovide = true
  neovide.setup_ui()
  neovide.setup_keys()

  eq(vim.o.guifont:match("SF Mono") ~= nil, true, "guifont")
  eq(vim.o.guifontwide:match("PingFang SC") ~= nil, true, "guifontwide")
  eq(vim.o.linespace, 2, "linespace")
  eq(vim.g.neovide_scale_factor, 1.0, "scale factor")
  eq(vim.fn.maparg("<D-s>", "n") ~= "", true, "Cmd-S")
  eq(vim.fn.maparg("<D-c>", "v") ~= "", true, "Cmd-C")
  eq(vim.fn.maparg("<D-v>", "n") ~= "", true, "Cmd-V")
  eq(vim.fn.maparg("<D-p>", "n") ~= "", true, "Cmd-P")
  eq(vim.fn.maparg("<D-0>", "n") ~= "", true, "Cmd-0")
end)

vim.g.neovide = saved.neovide
vim.env.PATH = saved.path
vim.env.LANG = saved.lang
vim.env.LC_CTYPE = saved.lc_ctype
vim.env.NEXT_VIM_GUI_PATH = saved.gui_path
vim.o.shell = saved.shell
vim.o.guifont = saved.guifont
vim.o.guifontwide = saved.guifontwide
vim.o.linespace = saved.linespace
vim.fn.delete(tmp, "rf")

io.write(string.format("\n%d passed, %d failed\n", pass_count, fail_count))
if fail_count > 0 then
  os.exit(1)
end
os.exit(0)

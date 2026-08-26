#!/usr/bin/env -S nvim --headless -u NONE -l
-- Run: nvim --headless -u NONE -l tests/test_surround.lua

local script_dir = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local root = script_dir .. "../"
package.path = root .. "lua/?.lua;" .. root .. "lua/?/init.lua;" .. package.path

local surround = require("configs.surround")

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

--- Load `lines` into a scratch buffer, select from (srow,scol) to (erow,ecol)
--- in 1-indexed byte coordinates, run `fn`, return the resulting lines.
local function with_selection(lines, srow, scol, erow, ecol, mode, fn)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.fn.setpos("'<", { buf, srow, scol, 0 })
  vim.fn.setpos("'>", { buf, erow, ecol, 0 })
  -- visualmode() reports the last used mode; set it explicitly.
  vim.cmd("normal! " .. (mode == "V" and "V" or "v") .. "\27")
  vim.fn.setpos("'<", { buf, srow, scol, 0 })
  vim.fn.setpos("'>", { buf, erow, ecol, 0 })
  fn()
  local out = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  vim.api.nvim_buf_delete(buf, { force = true })
  return out
end

--- Drive a REAL visual selection with normal-mode keys, then run `fn` while
--- still in visual mode -- the way the keymaps actually invoke it. The
--- `'< '>` marks are deliberately left holding a stale earlier selection.
local function with_real_visual(lines, cursor, keys, fn)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.cmd("normal! ggv3l\27") -- stale '< '>
  vim.api.nvim_win_set_cursor(0, cursor)
  vim.cmd("normal! " .. keys)
  fn()
  local out = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  vim.api.nvim_buf_delete(buf, { force = true })
  return out
end

io.write("\n=== mirror: bracket pairs ===\n")

test("( mirrors to )", function() eq(surround.mirror("("), ")") end)
test("[ mirrors to ]", function() eq(surround.mirror("["), "]") end)
test("{ mirrors to }", function() eq(surround.mirror("{"), "}") end)
test("< mirrors to >", function() eq(surround.mirror("<"), ">") end)
test("(( mirrors to ))", function() eq(surround.mirror("(("), "))") end)
test("({ mirrors to })", function() eq(surround.mirror("({"), "})") end)

io.write("\n=== mirror: symmetric delimiters ===\n")

test("** is used verbatim", function() eq(surround.mirror("**"), "**") end)
test('" is used verbatim', function() eq(surround.mirror('"'), '"') end)
test("~~ is used verbatim", function() eq(surround.mirror("~~"), "~~") end)
test("$$ is used verbatim", function() eq(surround.mirror("$$"), "$$") end)
test("empty stays empty", function() eq(surround.mirror(""), "") end)

io.write("\n=== mirror: html tags ===\n")

test("<div> closes with </div>", function() eq(surround.mirror("<div>"), "</div>") end)
test("tag with attributes", function() eq(surround.mirror('<div class="x">'), "</div>") end)
test("hyphenated tag", function() eq(surround.mirror("<my-widget>"), "</my-widget>") end)
test("namespaced tag", function() eq(surround.mirror("<ns:tag>"), "</ns:tag>") end)
test("closing tag is not re-closed", function() eq(surround.mirror("</div>"), "</div>") end)

io.write("\n=== mirror: prefixed brackets ===\n")

test("\\textbf{ closes with }", function() eq(surround.mirror("\\textbf{"), "}") end)
test("func( closes with )", function() eq(surround.mirror("func("), ")") end)
test("\\begin{env}{ closes with }", function() eq(surround.mirror("\\left{"), "}") end)

io.write("\n=== wrap ===\n")

test("wrap ascii selection", function()
  local out = with_selection({ "hello world" }, 1, 1, 1, 5, "v", function()
    surround.wrap("(", ")")
  end)
  eq(out[1], "(hello) world")
end)

test("wrap multibyte selection keeps characters intact", function()
  -- 你好世界 : each char is 3 bytes; select 你好 = bytes 1..4 ('> is first byte of 好)
  local out = with_selection({ "你好世界" }, 1, 1, 1, 4, "v", function()
    surround.wrap("[", "]")
  end)
  eq(out[1], "[你好]世界")
end)

test("wrap emoji selection", function()
  local out = with_selection({ "a🎉b" }, 1, 2, 1, 2, "v", function()
    surround.wrap("(", ")")
  end)
  eq(out[1], "a(🎉)b")
end)

test("wrap with arbitrary text", function()
  local out = with_selection({ "bold me" }, 1, 1, 1, 4, "v", function()
    surround.wrap("**", "**")
  end)
  eq(out[1], "**bold** me")
end)

test("wrap with html tag", function()
  local out = with_selection({ "text" }, 1, 1, 1, 4, "v", function()
    surround.wrap("<b>", surround.mirror("<b>"))
  end)
  eq(out[1], "<b>text</b>")
end)

test("wrap linewise selection", function()
  local out = with_selection({ "line" }, 1, 1, 1, 4, "V", function()
    surround.wrap("{", "}")
  end)
  eq(out[1], "{line}")
end)

test("wrap multiline selection", function()
  local out = with_selection({ "aaa", "bbb" }, 1, 1, 2, 3, "v", function()
    surround.wrap("(", ")")
  end)
  eq(out[1], "(aaa")
  eq(out[2], "bbb)")
end)

io.write("\n=== unwrap ===\n")

test("unwrap when delimiters are inside the selection", function()
  local out = with_selection({ "(hello) world" }, 1, 1, 1, 7, "v", function()
    surround.unwrap("(", ")")
  end)
  eq(out[1], "hello world")
end)

test("unwrap when delimiters are outside the selection", function()
  local out = with_selection({ "(hello) world" }, 1, 2, 1, 6, "v", function()
    surround.unwrap("(", ")")
  end)
  eq(out[1], "hello world")
end)

test("unwrap multibyte content", function()
  local out = with_selection({ "「你好」" }, 1, 1, 1, 10, "v", function()
    surround.unwrap("「", "」")
  end)
  eq(out[1], "你好")
end)

test("unwrap multi-char delimiters", function()
  local out = with_selection({ "**bold**" }, 1, 1, 1, 8, "v", function()
    surround.unwrap("**", "**")
  end)
  eq(out[1], "bold")
end)

test("unwrap html tag", function()
  local out = with_selection({ "<b>text</b>" }, 1, 1, 1, 11, "v", function()
    surround.unwrap("<b>", "</b>")
  end)
  eq(out[1], "text")
end)

test("unwrap leaves non-matching selection alone", function()
  local out = with_selection({ "hello" }, 1, 1, 1, 5, "v", function()
    surround.unwrap("(", ")")
  end)
  eq(out[1], "hello")
end)

test("unwrap does not eat a lone delimiter", function()
  -- "(a" is not a complete pair; must stay untouched
  local out = with_selection({ "(a" }, 1, 1, 1, 2, "v", function()
    surround.unwrap("(", ")")
  end)
  eq(out[1], "(a")
end)

io.write("\n=== round trip ===\n")

test("wrap then unwrap restores the original", function()
  local out = with_selection({ "你好世界" }, 1, 1, 1, 4, "v", function()
    surround.wrap("(", ")")
    -- selection now covers (你好) : bytes 1..8, '> at first byte of ')'
    vim.fn.setpos("'<", { 0, 1, 1, 0 })
    vim.fn.setpos("'>", { 0, 1, 8, 0 })
    surround.unwrap("(", ")")
  end)
  eq(out[1], "你好世界")
end)


io.write("\n=== real visual mode (stale '< '> marks) ===\n")

test("viw then wrap uses the CURRENT selection", function()
  local out = with_real_visual({ "asdasdas asd safsf" }, { 1, 9 }, "viw", function()
    surround.wrap('"', '"')
  end)
  eq(out[1], 'asdasdas "asd" safsf')
end)

test("viw on a cjk word", function()
  local out = with_real_visual({ "前面 你好 后面" }, { 1, 10 }, "viw", function()
    surround.wrap("(", ")")
  end)
  eq(out[1], "前面 (你好) 后面")
end)

test("backwards selection (cursor before anchor)", function()
  local out = with_real_visual({ "abc def ghi" }, { 1, 6 }, "vhh", function()
    surround.wrap("[", "]")
  end)
  eq(out[1], "abc [def] ghi")
end)

test("linewise V", function()
  local out = with_real_visual({ "hello" }, { 1, 0 }, "V", function()
    surround.wrap("{", "}")
  end)
  eq(out[1], "{hello}")
end)

test("viw then unwrap", function()
  local out = with_real_visual({ 'x "asd" y' }, { 1, 3 }, "viw", function()
    surround.unwrap('"', '"')
  end)
  eq(out[1], "x asd y")
end)

test("multiline visual selection", function()
  local out = with_real_visual({ "aaa", "bbb" }, { 1, 0 }, "vj$", function()
    surround.wrap("<", ">")
  end)
  eq(out[1], "<aaa")
  eq(out[2], "bbb>")
end)

test("leaves visual mode afterwards", function()
  with_real_visual({ "abc" }, { 1, 0 }, "viw", function()
    surround.wrap("(", ")")
  end)
  local mode = vim.fn.mode()
  if mode == "v" or mode == "V" or mode == "\22" then
    error("still in visual mode: " .. mode)
  end
end)


io.write("\n=== picker (vim.ui.select / vim.ui.input) ===\n")

--- Drive the picker by stubbing vim.ui.select/input. `choose` matches an
--- entry by its icon; `inputs` answers the prompts in order.
local function with_picker(lines, cursor, keys, choose, inputs, fn)
  local select_orig, input_orig = vim.ui.select, vim.ui.input
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.cmd("normal! ggv3l\27")
  vim.api.nvim_win_set_cursor(0, cursor)
  vim.cmd("normal! " .. keys)

  local asked = 0
  vim.ui.select = function(items, _, cb)
    for _, it in ipairs(items) do
      if it.icon == choose then
        return cb(it)
      end
    end
    cb(nil)
  end
  vim.ui.input = function(_, cb)
    asked = asked + 1
    cb(inputs[asked])
  end

  local ok, err = pcall(fn)
  vim.ui.select, vim.ui.input = select_orig, input_orig
  local out = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  vim.api.nvim_buf_delete(buf, { force = true })
  if not ok then
    error(err, 0)
  end
  return out
end

test("preset: double quote", function()
  local out = with_picker({ "aaa bbb ccc" }, { 1, 4 }, "viw", '"', {}, surround.wrap_prompt)
  eq(out[1], 'aaa "bbb" ccc')
end)

test("preset: cjk corner bracket", function()
  local out = with_picker({ "前面 你好 后面" }, { 1, 10 }, "viw", "「」", {}, surround.wrap_prompt)
  eq(out[1], "前面 「你好」 后面")
end)

test("preset: markdown bold", function()
  local out = with_picker({ "make bold now" }, { 1, 5 }, "viw", "**", {}, surround.wrap_prompt)
  eq(out[1], "make **bold** now")
end)

test("tag entry asks for a name", function()
  local out = with_picker({ "content" }, { 1, 0 }, "viw", "<t>", { "div" }, surround.wrap_prompt)
  eq(out[1], "<div>content</div>")
end)

test("custom entry asks for both sides", function()
  local out = with_picker({ "x" }, { 1, 0 }, "viw", "\u{270e}", { "\\textbf{", "}" }, surround.wrap_prompt)
  eq(out[1], "\\textbf{x}")
end)

test("cancelling the picker changes nothing", function()
  local out = with_picker({ "abc" }, { 1, 0 }, "viw", "NO_SUCH_ENTRY", {}, surround.wrap_prompt)
  eq(out[1], "abc")
end)

test("cancelling the input changes nothing", function()
  local out = with_picker({ "abc" }, { 1, 0 }, "viw", "\u{270e}", { nil }, surround.wrap_prompt)
  eq(out[1], "abc")
end)

test("unwrap through the picker", function()
  local out = with_picker({ 'x "asd" y' }, { 1, 3 }, "viw", '"', {}, surround.unwrap_prompt)
  eq(out[1], "x asd y")
end)

test("menu lines are display-width aligned", function()
  local widths = {}
  local select_orig = vim.ui.select
  vim.ui.select = function(items, opts)
    for _, it in ipairs(items) do
      -- column where the description starts must be identical everywhere
      local line = opts.format_item(it)
      local desc_at = vim.fn.strdisplaywidth(line:match("^(.-)%S+[^%S]*$") or "")
      widths[#widths + 1] = vim.fn.strdisplaywidth(line) - vim.fn.strdisplaywidth(it.desc)
    end
  end
  vim.fn.setpos("'<", { 0, 1, 1, 0 })
  vim.fn.setpos("'>", { 0, 1, 1, 0 })
  surround.wrap_prompt()
  vim.ui.select = select_orig
  for i = 2, #widths do
    if widths[i] ~= widths[1] then
      error(string.format("entry %d starts at column %d, expected %d", i, widths[i], widths[1]))
    end
  end
end)

io.write(string.format("\n%d passed, %d failed\n", pass_count, fail_count))
if fail_count > 0 then
  os.exit(1)
end
os.exit(0)

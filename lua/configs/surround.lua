-- Wrap / unwrap a visual selection with an arbitrary pair of strings.
--
-- Beyond the fixed bracket pairs this also accepts free-form text, so the
-- right-hand side has to be inferred from the left: see M.mirror.

local M = {}

local MIRROR = {
  ["("] = ")",
  ["["] = "]",
  ["{"] = "}",
  ["<"] = ">",
}

--- Infer the closing text for an opening string.
---
--- `<div class="x">` -> `</div>`   (html/xml tag)
--- `\textbf{`        -> `}`        (trailing brackets are mirrored)
--- `((`              -> `))`
--- `**`              -> `**`       (no brackets: used verbatim)
---
--- @param left string
--- @return string
function M.mirror(left)
  if left == "" then
    return ""
  end

  -- An opening tag closes with </name>, ignoring any attributes.
  if left:sub(-1) == ">" and not left:match("^<%s*/") then
    local tag = left:match("^<%s*([%w_:%-%.]+)")
    if tag then
      return "</" .. tag .. ">"
    end
  end

  -- Mirror the trailing run of bracket characters, right to left. This keeps
  -- a prefix like `\textbf` out of the closing text.
  local out = {}
  for i = #left, 1, -1 do
    local mirrored = MIRROR[left:sub(i, i)]
    if not mirrored then
      break
    end
    out[#out + 1] = mirrored
  end

  if #out > 0 then
    return table.concat(out)
  end

  -- Symmetric delimiters (**, ", ~~, $$ ...) close with themselves.
  return left
end

local function in_visual_mode()
  local mode = vim.fn.mode()
  return mode == "v" or mode == "V" or mode == "\22"
end

--- Byte range of the visual selection, as 0-indexed end-exclusive coordinates
--- suitable for nvim_buf_get_text/nvim_buf_set_text.
---
--- While visual mode is active the `'<` / `'>` marks still hold the PREVIOUS
--- selection -- they are only updated on leaving visual mode -- so the live
--- endpoints have to come from `v` and `.` instead. The marks are still the
--- right source when called from outside visual mode (e.g. `:'<,'>`).
---
--- @return integer? srow, integer? scol, integer? erow, integer? ecol
function M.range()
  local s, e, mode
  if in_visual_mode() then
    s, e, mode = vim.fn.getpos("v"), vim.fn.getpos("."), vim.fn.mode()
  else
    s, e, mode = vim.fn.getpos("'<"), vim.fn.getpos("'>"), vim.fn.visualmode()
  end

  local srow, scol = s[2], s[3]
  local erow, ecol = e[2], e[3]

  if srow > erow or (srow == erow and scol > ecol) then
    srow, erow = erow, srow
    scol, ecol = ecol, scol
  end

  if mode == "\22" then
    vim.notify("Blockwise visual mode is not supported for pair wrap/unwrap", vim.log.levels.WARN)
    return nil
  end

  local last_line = vim.fn.getline(erow)

  if mode == "V" then
    scol = 1
    ecol = #last_line
  else
    -- `'>` points at the FIRST byte of the last selected character, so a
    -- multibyte character would be cut in half. Extend to its last byte.
    local char = vim.fn.strpart(last_line, ecol - 1, 1, true)
    ecol = ecol + math.max(#char - 1, 0)
  end

  -- `v$` and linewise selections can push the column past the end of the line.
  ecol = math.min(ecol, #last_line)

  return srow - 1, math.max(scol - 1, 0), erow - 1, math.max(ecol, 0)
end

--- Capture the selection range, then leave visual mode.
---
--- Leaving matters because the buffer is about to change under the selection,
--- and because vim.fn.input() would otherwise drop out of visual mode itself,
--- after the range was needed.
---
--- @return table? range {srow, scol, erow, ecol}
function M.capture()
  local srow, scol, erow, ecol = M.range()
  if in_visual_mode() then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
  end
  if srow == nil then
    return nil
  end
  return { srow, scol, erow, ecol }
end

local function get_text(bufnr, srow, scol, erow, ecol)
  return table.concat(vim.api.nvim_buf_get_text(bufnr, srow, scol, erow, ecol, {}), "\n")
end

local function set_text(bufnr, srow, scol, erow, ecol, text)
  vim.api.nvim_buf_set_text(bufnr, srow, scol, erow, ecol, vim.split(text, "\n", { plain = true }))
end

--- Wrap the selection in `left` ... `right`.
--- @param left string
--- @param right string
--- @param range table? pre-captured range; captured from the selection if omitted
function M.wrap(left, right, range)
  range = range or M.capture()
  if range == nil then
    return
  end
  local srow, scol, erow, ecol = range[1], range[2], range[3], range[4]
  local bufnr = vim.api.nvim_get_current_buf()
  local selected = get_text(bufnr, srow, scol, erow, ecol)
  set_text(bufnr, srow, scol, erow, ecol, left .. selected .. right)
end

--- Remove `left` / `right` from around the selection.
---
--- Works whether the delimiters are inside the selection or immediately
--- outside it, so both `vi"` and `va"` style selections behave.
--- @param left string
--- @param right string
--- @param range table? pre-captured range; captured from the selection if omitted
function M.unwrap(left, right, range)
  range = range or M.capture()
  if range == nil then
    return
  end
  local srow, scol, erow, ecol = range[1], range[2], range[3], range[4]
  local bufnr = vim.api.nvim_get_current_buf()
  local selected = get_text(bufnr, srow, scol, erow, ecol)

  -- Case 1: the selection includes the delimiters.
  if
    #selected >= #left + #right
    and selected:sub(1, #left) == left
    and selected:sub(-#right) == right
  then
    set_text(bufnr, srow, scol, erow, ecol, selected:sub(#left + 1, #selected - #right))
    return
  end

  -- Case 2: the delimiters sit just outside the selection.
  local before_ok, before = pcall(get_text, bufnr, srow, math.max(scol - #left, 0), srow, scol)
  local after_ok, after = pcall(get_text, bufnr, erow, ecol, erow, ecol + #right)
  if before_ok and after_ok and before == left and after == right then
    set_text(bufnr, erow, ecol, erow, ecol + #right, "")
    set_text(bufnr, srow, math.max(scol - #left, 0), srow, scol, "")
    return
  end

  vim.notify("Selection is not wrapped by expected pair", vim.log.levels.INFO)
end

-- ── Interactive picker ──────────────────────────────────────────────
--
-- vim.ui.select / vim.ui.input are used rather than vim.fn.input so that
-- dressing.nvim renders them as floating windows.

--- Presets offered by the picker. `nil` left means "ask for the text".
local PRESETS = {
  { icon = "\"", left = '"', desc = "double quote" },
  { icon = "'", left = "'", desc = "single quote" },
  { icon = "()", left = "(", desc = "parentheses" },
  { icon = "[]", left = "[", desc = "brackets" },
  { icon = "{}", left = "{", desc = "braces" },
  { icon = "<>", left = "<", desc = "angle brackets" },
  { icon = "`", left = "`", desc = "backtick" },
  { icon = "**", left = "**", desc = "bold (markdown)" },
  { icon = "*", left = "*", desc = "italic (markdown)" },
  { icon = "~~", left = "~~", desc = "strikethrough" },
  { icon = "$", left = "$", desc = "inline math" },
  { icon = "「」", left = "\u{300c}", right = "\u{300d}", desc = "cjk corner bracket" },
  { icon = "（）", left = "\u{ff08}", right = "\u{ff09}", desc = "fullwidth parens" },
  { icon = "“”", left = "\u{201c}", right = "\u{201d}", desc = "curly quotes" },
  { icon = "<t>", left = nil, kind = "tag", desc = "html/xml tag\u{2026}" },
  { icon = "\u{270e}", left = nil, kind = "custom", desc = "custom text\u{2026}" },
}

--- Flash the wrapped region so the edit is visible.
local function flash(range)
  if not (vim.hl and vim.hl.range) then
    return
  end
  local ns = vim.api.nvim_create_namespace("surround_flash")
  pcall(vim.hl.range, 0, ns, "IncSearch", { range[1], range[2] }, { range[3], range[4] }, {
    timeout = 180,
  })
end

--- Pad to a fixed DISPLAY width. string.format("%-6s") counts bytes, which
--- misaligns every cjk/fullwidth entry in the menu.
local function pad(str, width)
  return str .. string.rep(" ", math.max(width - vim.fn.strdisplaywidth(str), 0))
end

--- One-line preview of what a preset does, e.g. `(` -> `(\u{00b7}\u{00b7}\u{00b7})`.
local function preview(left, right)
  return left .. "\u{00b7}\u{00b7}\u{00b7}" .. right
end

--- Build the display strings for vim.ui.select.
local function format_item(item)
  local left_col = pad(item.icon, 5)
  if item.kind then
    return "  " .. left_col .. pad("", 10) .. item.desc
  end
  local right = item.right or M.mirror(item.left)
  return "  " .. left_col .. pad(preview(item.left, right), 10) .. item.desc
end

--- Ask for arbitrary text, infer the closing side, then hand both to `apply`.
local function ask_custom(prompt, apply)
  vim.ui.input({ prompt = prompt }, function(left)
    if not left or left == "" then
      return
    end
    vim.ui.input({ prompt = "Closing: ", default = M.mirror(left) }, function(right)
      if not right then
        return
      end
      apply(left, right)
    end)
  end)
end

--- Ask for a tag name, then wrap in <name> ... </name>.
local function ask_tag(apply)
  vim.ui.input({ prompt = "Tag name: " }, function(name)
    if not name or name == "" then
      return
    end
    name = vim.trim(name)
    local left = "<" .. name .. ">"
    apply(left, M.mirror(left))
  end)
end

--- Shared picker for both wrap and unwrap.
--- @param title string
--- @param apply fun(left: string, right: string)
local function pick(title, apply)
  vim.ui.select(PRESETS, {
    prompt = title,
    format_item = format_item,
  }, function(item)
    if not item then
      return
    end
    if item.kind == "custom" then
      ask_custom("Surround with: ", apply)
    elseif item.kind == "tag" then
      ask_tag(apply)
    else
      apply(item.left, item.right or M.mirror(item.left))
    end
  end)
end

--- Pick a pair from a floating menu, then wrap the selection.
function M.wrap_prompt()
  local range = M.capture()
  if range == nil then
    return
  end
  pick("Surround with", function(left, right)
    M.wrap(left, right, range)
    -- The region grew by the opening text on its first line.
    flash({ range[1], range[2], range[3], range[4] + #left + #right })
  end)
end

--- Pick a pair from a floating menu, then unwrap the selection.
function M.unwrap_prompt()
  local range = M.capture()
  if range == nil then
    return
  end
  pick("Remove surround", function(left, right)
    M.unwrap(left, right, range)
    flash({ range[1], math.max(range[2] - #left, 0), range[3], math.max(range[4] - #left, 0) })
  end)
end

return M

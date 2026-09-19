-- Replace a multi-line `$$ ... $$` block with its rendered form.
--
-- render-markdown only ever conceals SINGLE-LINE formulas. `position = "center"`
-- swaps the source for inline virtual text, but its handler falls back to
-- "above" as soon as a block spans more than one line, and the "above" /
-- "below" paths draw virtual lines without concealing anything. A display
-- formula therefore shows up twice: once rendered, once as source.
--
-- This wraps the builtin handler instead of replacing it, so single-line
-- formulas keep their existing behaviour. For a block it:
--
--   1. re-anchors the virtual lines the builtin produced onto the neighbouring
--      line, because virtual lines attached to a concealed line are not drawn,
--   2. hides the source lines with `conceal_lines`.
--
-- The hiding mark opts out of the plugin's anti-conceal pass (`conceal = false`).
-- That pass reveals a whole block at once, which also brings back the builtin's
-- virtual lines and renders the formula twice again.
--
-- Hidden source lines are still real buffer lines, so `j` walks into them and
-- the cursor disappears for a few keystrokes. M.setup() maps `j` / `k` to step
-- over them.

local builtin = require("render-markdown.handler.latex")
local context = require("render-markdown.request.context")

--- Row the builtin hangs a block's virtual lines on, mirroring its own choice.
--- @param position string
--- @param node render.md.Node
--- @return integer
local function rendered_row(position, node)
  if position == "below" then
    return node.end_row
  end
  return node.start_row
end

--- Row to move those virtual lines to, once the block itself is concealed.
--- Prefers the side the formula was already rendered on.
--- @param buf integer
--- @param position string
--- @param node render.md.Node
--- @return integer? row, boolean? above lines are drawn above `row`
local function anchor(buf, position, node)
  local before = node.start_row > 0 and node.start_row - 1 or nil
  local after = node.end_row + 1 < vim.api.nvim_buf_line_count(buf) and node.end_row + 1 or nil

  local first, second = before, after
  if position == "below" then
    first, second = after, before
  end

  local row = first or second
  if not row then
    -- Block fills the buffer: nothing to attach to, leave it rendered as-is.
    return nil, nil
  end
  -- Drawing above the following line puts the formula directly below the block.
  return row, row == after
end

--- @param buf integer
--- @param row integer
--- @return integer
local function line_length(buf, row)
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
  return line and #line or 0
end

--- @param ctx render.md.handler.Context
--- @return render.md.Mark[]
local function parse(ctx)
  -- `extends = false` stops the framework from running the builtin, we drive it
  -- here so its marks can be adjusted before they are handed back.
  local marks = builtin.parse(ctx)

  -- Nodes accumulate across the pass and are only rendered on the last root.
  if not ctx.last then
    return marks
  end

  local config = context.get(ctx.buf).config.latex
  if not config.enabled then
    return marks
  end

  --- @type table<integer, render.md.Node>
  local blocks = {}
  for _, node in ipairs(context.get(ctx.buf).latex:get()) do
    if node:height() > 1 then
      blocks[rendered_row(config.position, node)] = node
    end
  end

  --- @type render.md.Mark[]
  local conceal = {}
  for _, mark in ipairs(marks) do
    local node = mark.opts.virt_lines and blocks[mark.start_row]
    if node then
      local row, above = anchor(ctx.buf, config.position, node)
      if row then
        mark.start_row = row
        mark.opts.virt_lines_above = above
        conceal[#conceal + 1] = {
          modes = config.render_modes,
          conceal = false,
          start_row = node.start_row,
          start_col = 0,
          opts = {
            end_row = node.end_row,
            end_col = line_length(ctx.buf, node.end_row),
            conceal_lines = "",
          },
        }
      end
    end
  end

  return vim.list_extend(marks, conceal)
end

local M = {}

--- @type render.md.Handler
M.handler = { extends = false, parse = parse }

--- Namespace the marks above are written to.
local NS = "render-markdown.nvim"

--- Is `row` hidden by one of our `conceal_lines` marks? Marks start on the
--- block's first row and span the rest, so overlapping marks have to be asked
--- for explicitly.
--- @param buf integer
--- @param row integer 0-indexed
--- @return boolean
local function hidden(buf, row)
  local ns = vim.api.nvim_get_namespaces()[NS]
  if not ns then
    return false
  end
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, { row, 0 }, { row, -1 }, {
    details = true,
    overlap = true,
  })
  for _, mark in ipairs(marks) do
    if mark[4].conceal_lines then
      return true
    end
  end
  return false
end

--- Vertical motion that treats a concealed block as a single step.
--- @param key string
--- @return function
local function motion(key)
  local dir = key == "j" and 1 or -1
  return function()
    -- An explicit count asks for that many lines: take it literally.
    if vim.v.count > 0 then
      return key
    end
    local buf = vim.api.nvim_get_current_buf()
    local last = vim.api.nvim_buf_line_count(buf)
    local row, lines = vim.fn.line(".") + dir, 1
    while row >= 1 and row <= last and hidden(buf, row - 1) do
      row, lines = row + dir, lines + 1
    end
    if row < 1 or row > last then
      -- Only concealed lines left this way, staying put beats landing in them.
      return ""
    end
    return lines .. key
  end
end

--- @param buf integer
local function map(buf)
  for key, rhs in pairs({ j = "j", k = "k", ["<Down>"] = "j", ["<Up>"] = "k" }) do
    vim.keymap.set({ "n", "x" }, key, motion(rhs), {
      buffer = buf,
      expr = true,
      desc = "down/up over concealed latex blocks",
    })
  end
end

--- Map the motions in buffers render-markdown renders.
--- @param file_types string[]
function M.setup(file_types)
  vim.api.nvim_create_autocmd("FileType", {
    pattern = file_types,
    group = vim.api.nvim_create_augroup("RenderLatexMotion", { clear = true }),
    callback = function(args)
      map(args.buf)
    end,
  })
  -- This runs from the plugin's own config, i.e. after the FileType event that
  -- loaded it: the buffer that triggered it has to be picked up by hand.
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.tbl_contains(file_types, vim.bo[buf].filetype) then
      map(buf)
    end
  end
end

return M

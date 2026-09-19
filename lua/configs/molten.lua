-- Run notebook cells through a Jupyter kernel.
--
-- nvim-jupyter-client only EDITS notebooks: it renders an `.ipynb` as a python
-- buffer whose cells are separated by `# %% <cell id> [<execution count>]`
-- headers (`[MARKDOWN]` for prose cells) and has no kernel of its own. Molten
-- supplies the kernel but knows nothing about those headers -- it evaluates
-- lines, selections and motions. This maps one onto the other, so a single key
-- runs the cell the cursor is in.
--
-- Molten is a python remote plugin: `g:molten_*` has to be set before it starts,
-- hence the split between globals() and the keymaps in the plugin spec.

local M = {}

--- Matches both the plugin's `# %% <id> [<count>]` headers and a plain `# %%`
--- percent-cell, so ordinary python files with cell markers work too.
--- @param line string
--- @return table? { markdown: boolean }
local function header(line)
  if not line:match("^#%s*%%%%") then
    return nil
  end
  return { markdown = line:match("%[(.-)%]%s*$") == "MARKDOWN" }
end

--- Body of the cell the cursor sits in, header and trailing blanks excluded.
--- @param buf integer
--- @return table? { first: integer, last: integer, markdown: boolean }
local function cell(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local row = math.min(vim.api.nvim_win_get_cursor(0)[1], #lines)

  local top
  for i = row, 1, -1 do
    if header(lines[i]) then
      top = i
      break
    end
  end
  if not top then
    return nil
  end

  local bottom = #lines
  for i = top + 1, #lines do
    if header(lines[i]) then
      bottom = i - 1
      break
    end
  end

  local first = top + 1
  while bottom >= first and lines[bottom]:match("^%s*$") do
    bottom = bottom - 1
  end
  if first > bottom then
    return nil
  end

  return { first = first, last = bottom, markdown = header(lines[top]).markdown }
end

--- Move to the header of the next / previous cell.
--- @param step integer 1 or -1
function M.goto_cell(step)
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  for i = row + step, step > 0 and #lines or 1, step do
    if header(lines[i]) then
      vim.api.nvim_win_set_cursor(0, { i, 0 })
      return
    end
  end
  vim.notify("No further jupyter cell", vim.log.levels.INFO)
end

--- Evaluate the cell under the cursor.
--- @param opts? table { advance: boolean } move to the next cell afterwards
function M.run_cell(opts)
  opts = opts or {}
  local current = cell(vim.api.nvim_get_current_buf())
  if not current then
    vim.notify("No jupyter cell here, try <leader>jl or <leader>je", vim.log.levels.WARN)
    return
  end
  if current.markdown then
    vim.notify("Markdown cell, nothing to run", vim.log.levels.INFO)
    return
  end

  -- A remote plugin function, not a command. With two arguments it takes whole
  -- lines. Molten prompts for a kernel itself when the buffer has none yet.
  vim.fn.MoltenEvaluateRange(current.first, current.last)

  if opts.advance then
    M.goto_cell(1)
  end
end

--- Set before the remote plugin starts.
function M.globals()
  -- Without this molten renders images as a text placeholder.
  vim.g.molten_image_provider = "image.nvim"
  vim.g.molten_auto_open_output = true
  vim.g.molten_wrap_output = true
  vim.g.molten_output_show_more = true
  -- Defaults are 999999, which lets one plot take the whole screen.
  vim.g.molten_output_win_max_height = 24
  vim.g.molten_output_win_max_width = 120
  vim.g.molten_output_win_border = { "", "━", "", "" }
  vim.g.molten_virt_text_output = false
end

return M

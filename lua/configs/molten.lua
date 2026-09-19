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

--- Step back out of molten's output window. It is created non-focusable and
--- shares the notebook's tab, so `:q` would try to close the notebook instead.
local function leave_output()
  vim.cmd("wincmd p")
end

--- Reads the notebook on disk: whether it holds outputs worth restoring, and
--- the kernel it was written with.
--- @param path string
--- @return boolean has_outputs, string? kernel
local function notebook_info(path)
  if path:sub(-6) ~= ".ipynb" then
    return false, nil
  end
  local file = io.open(path, "r")
  if not file then
    return false, nil
  end
  local body = file:read("*a")
  file:close()
  local ok, notebook = pcall(vim.json.decode, body)
  if not ok or type(notebook) ~= "table" or type(notebook.cells) ~= "table" then
    return false, nil
  end

  local has_outputs = false
  for _, cell in ipairs(notebook.cells) do
    if type(cell.outputs) == "table" and #cell.outputs > 0 then
      has_outputs = true
      break
    end
  end

  local kernel = vim.tbl_get(notebook, "metadata", "kernelspec", "name")
  return has_outputs, type(kernel) == "string" and kernel or nil
end

--- @return string[]
local function running_kernels()
  local ok, kernels = pcall(vim.fn.MoltenRunningKernels, true)
  if ok and type(kernels) == "table" then
    return kernels
  end
  return {}
end

--- Attach the kernel the notebook declares, so reopening one restores its
--- outputs on its own. Without a kernel there is nothing for molten to hang
--- imported outputs off, and the notebook comes up blank.
---
--- Retries because this runs while the buffer is still being set up: molten is
--- a python remote plugin, and until its host process answers, the kernel list
--- comes back empty and there is nothing to match the notebook against.
--- @param buf integer
--- @param attempt? integer
local function auto_init(buf, attempt)
  attempt = attempt or 1
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local has_outputs, kernel = notebook_info(vim.api.nvim_buf_get_name(buf))
  -- Only for a notebook with something to restore: opening a fresh one should
  -- not cost a kernel process until something is actually run.
  if not has_outputs or not kernel or #running_kernels() > 0 then
    return
  end

  local ok, available = pcall(vim.fn.MoltenAvailableKernels)
  if not ok or type(available) ~= "table" or #available == 0 then
    if attempt < 10 then
      vim.defer_fn(function()
        auto_init(buf, attempt + 1)
      end, 200)
    end
    return
  end

  -- Notebooks routinely name a kernel that does not exist on this machine;
  -- staying quiet beats molten's "Could not initialize kernel" on every open.
  if vim.tbl_contains(available, kernel) then
    pcall(vim.cmd, "MoltenInit " .. kernel)
  end
end

--- @param buf integer
local function map_notebook(buf)
  vim.keymap.set("n", "<S-CR>", function()
    M.run_cell({ advance = true })
  end, { buffer = buf, desc = "Run cell and advance" })
end

--- Autocmds and buffer-local keymaps. Called once, when molten loads.
--- @param file_types string[] filetypes molten is loaded for
function M.setup(file_types)
  local group = vim.api.nvim_create_augroup("MoltenExtras", { clear = true })

  -- Shift+Enter is mapped per buffer so it only means "run" in a notebook.
  vim.api.nvim_create_autocmd("FileType", {
    pattern = file_types,
    group = group,
    callback = function(args)
      map_notebook(args.buf)
      -- Scheduled: nvim-jupyter-client sets the filetype partway through
      -- rendering, and the cell text has to be there before molten reads it.
      vim.schedule(function()
        auto_init(args.buf)
      end)
    end,
  })
  -- This runs from molten's config, i.e. after the FileType event that loaded
  -- it, so the buffer that triggered it needs handling by hand.
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.tbl_contains(file_types, vim.bo[buf].filetype) then
      map_notebook(buf)
      vim.schedule(function()
        auto_init(buf)
      end)
    end
  end

  -- Leaving the output window, rather than :q.
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "molten_output",
    group = group,
    callback = function(args)
      for _, lhs in ipairs({ "<Esc>", "q", "<leader>jo" }) do
        vim.keymap.set("n", lhs, leave_output, {
          buffer = args.buf,
          desc = "Leave cell output",
        })
      end
    end,
  })

  -- Restore the outputs stored in the .ipynb, so last session's plot is on
  -- screen without re-running the cell. Needs a kernel to hang them off, which
  -- is exactly what has just been created.
  vim.api.nvim_create_autocmd("User", {
    pattern = "MoltenInitPost",
    group = group,
    callback = function()
      local has_outputs = notebook_info(vim.fn.expand("%:p"))
      if has_outputs then
        pcall(vim.cmd, "MoltenImportOutput")
      end
    end,
  })

  -- And write them back when the notebook goes away.
  --
  -- Not on write: nvim-jupyter-client claims BufWriteCmd, and a Cmd event
  -- suppresses BufWritePre/BufWritePost entirely, so there is no post-write
  -- hook to use. Adding another BufWriteCmd would make this responsible for
  -- writing the file, which is not a risk worth taking for a side effect.
  -- These two events only observe, and match what was asked for: keep the
  -- output when the notebook is closed. The bang means "in place" -- without
  -- it molten writes a copy-of-<name>.ipynb instead.
  vim.api.nvim_create_autocmd({ "BufWinLeave", "VimLeavePre" }, {
    pattern = "*.ipynb",
    group = group,
    callback = function()
      if #running_kernels() > 0 then
        pcall(vim.cmd, "MoltenExportOutput!")
      end
    end,
  })

  vim.api.nvim_create_user_command("JupyterSaveOutput", function()
    pcall(vim.cmd, "MoltenExportOutput!")
  end, { desc = "Write cell outputs into the .ipynb now" })
end

--- Set before the remote plugin starts.
function M.globals()
  -- Without this molten renders images as a text placeholder.
  vim.g.molten_image_provider = "image.nvim"
  vim.g.molten_auto_open_output = true
  -- Default "open_then_enter" costs two presses of <leader>jo once the window
  -- has been closed: one to reopen, one to step in. Makes it a real toggle
  -- against the <Esc> / q / <leader>jo mappings added in setup().
  vim.g.molten_enter_output_behavior = "open_and_enter"
  vim.g.molten_wrap_output = true
  vim.g.molten_output_show_more = true
  -- Defaults are 999999, which lets one plot take the whole screen.
  vim.g.molten_output_win_max_height = 24
  vim.g.molten_output_win_max_width = 120
  -- Each edge is a { char, highlight } pair rather than a bare string. The
  -- "N More Lines" footer, which only appears once output is taller than
  -- output_win_max_height, indexes element [1] of the bottom edge for its
  -- highlight; against a bare "━" that is a second character which does not
  -- exist, and molten raises IndexError from MoltenTick -- on a timer, so it
  -- repeats until the editor is unusable.
  vim.g.molten_output_win_border = {
    { "", "FloatBorder" },
    { "━", "FloatBorder" },
    { "", "FloatBorder" },
    { "", "FloatBorder" },
  }
  vim.g.molten_virt_text_output = false
end

return M

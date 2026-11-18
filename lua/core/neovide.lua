--- Neovide-specific bootstrap: PATH, GUI options, and macOS shortcuts.
---
--- A Neovide launched from Finder (or "Open With") inherits launchd's minimal
--- PATH, not the PATH built by .zshrc. Before this module, only the python
--- provider was pinned (core/python.lua); everything else that shells out --
--- chafa previews in oil, rg/fd in Telescope, formatters in conform, latexmk
--- in VimTeX, the floating terminal, DAP adapters -- saw /usr/bin only. Fill
--- in the usual Homebrew/local/conda/Mason directories here, before plugins
--- and providers probe them.
local M = {}

local function split_path(value)
  local entries = {}
  for dir in tostring(value or ""):gmatch("[^:]+") do
    entries[#entries + 1] = dir
  end
  return entries
end

--- Conda envs are where pynvim, uv and Jupyter usually live. A GUI launch
--- cannot see `conda activate`, so add the base and every env's bin directory.
local function conda_bins()
  local bins = {}
  if vim.env.CONDA_PREFIX and vim.env.CONDA_PREFIX ~= "" then
    bins[#bins + 1] = vim.env.CONDA_PREFIX .. "/bin"
  end

  for _, root in ipairs({
    "/opt/homebrew/Caskroom/miniforge/base",
    vim.fn.expand("~/miniforge3"),
    vim.fn.expand("~/miniconda3"),
    vim.fn.expand("~/anaconda3"),
    vim.fn.expand("~/.conda"),
  }) do
    bins[#bins + 1] = root .. "/bin"
    bins[#bins + 1] = root .. "/condabin"
    vim.list_extend(bins, vim.fn.glob(root .. "/envs/*/bin", false, true))
  end

  return bins
end

--- Paths to put in front of the launchd PATH. NEXT_VIM_GUI_PATH (a
--- colon-separated list) goes first so a user can add machine-specific tools
--- without editing this file.
local function gui_paths()
  local entries = {}
  vim.list_extend(entries, split_path(vim.env.NEXT_VIM_GUI_PATH))
  vim.list_extend(entries, {
    "/opt/homebrew/bin",
    "/opt/homebrew/sbin",
    "/opt/homebrew/opt/llvm/bin",
    vim.fn.expand("~/.local/bin"),
    vim.fn.expand("~/.local/share/nvim/mason/bin"),
    vim.fn.expand("~/.cargo/bin"),
    vim.fn.expand("~/.npm-global/bin"),
    vim.fn.expand("~/.virtualenvs/neovim/bin"),
  })
  vim.list_extend(entries, conda_bins())
  entries[#entries + 1] = "/usr/local/bin"
  vim.list_extend(entries, split_path(vim.env.PATH))

  local seen = {}
  local paths = {}
  for _, dir in ipairs(entries) do
    dir = vim.fn.expand(dir)
    if dir ~= "" and not seen[dir] and vim.fn.isdirectory(dir) == 1 then
      seen[dir] = true
      paths[#paths + 1] = dir
    end
  end
  return paths
end

--- Called before core.python and lazy.nvim, so every child process sees the
--- same PATH. Safe in terminal Neovim: it does nothing outside Neovide.
function M.setup_env()
  if not vim.g.neovide then
    return
  end

  local paths = gui_paths()
  if #paths > 0 then
    vim.env.PATH = table.concat(paths, ":")
  end

  -- launchd may start a GUI without a locale; UTF-8 keeps chafa, latexmk and
  -- friends from mangling non-ASCII output.
  if not vim.env.LANG or vim.env.LANG == "" then
    vim.env.LANG = "en_US.UTF-8"
  end
  if not vim.env.LC_CTYPE or vim.env.LC_CTYPE == "" then
    vim.env.LC_CTYPE = vim.env.LANG
  end

  -- :terminal uses 'shell'. launchd normally sets SHELL, but not always.
  if vim.o.shell == "" or vim.o.shell == "/bin/sh" then
    vim.o.shell = vim.env.SHELL or "/bin/zsh"
  end
end

--- Typography and Neovide's own GUI knobs. Keep the font list from the old
--- core.options block: SF Mono first, Nerd Font for devicons, Symbols Nerd
--- Font for stray PUA icons, emoji, and PingFang SC for CJK.
function M.setup_ui()
  if not vim.g.neovide then
    return
  end

  vim.o.guifont = "SF Mono,Maple Mono NF,Symbols Nerd Font,Apple Color Emoji,PingFang SC:h14"
  vim.o.guifontwide = "PingFang SC:h14,Apple Color Emoji:h14"
  vim.o.linespace = 2

  vim.g.neovide_scale_factor = 1.0
  vim.g.neovide_cursor_animation_length = 0.10
  vim.g.neovide_cursor_trail_size = 0.8
  vim.g.neovide_cursor_animate_in_insert_mode = true
  vim.g.neovide_cursor_animate_command_line = true
  vim.g.neovide_scroll_animation_length = 0.2
  vim.g.neovide_position_animation_length = 0.10
  vim.g.neovide_hide_mouse_when_typing = true
  vim.g.neovide_refresh_rate = 60
  vim.g.neovide_refresh_rate_idle = 5
  vim.g.neovide_remember_window_size = true
  vim.g.neovide_confirm_quit = true
  vim.g.neovide_theme = "auto"
end

local function paste()
  vim.api.nvim_paste(vim.fn.getreg("+"), true, -1)
end

local function copy_selection()
  vim.cmd([[normal! "+y]])
end

local function copy_line()
  vim.cmd([[normal! "+yy]])
end

local function cut_selection()
  vim.cmd([[normal! "+d]])
end

local function cut_line()
  vim.cmd([[normal! "+dd]])
end

local function save()
  if vim.bo.buftype ~= "" or not vim.bo.modifiable then
    return
  end

  if vim.api.nvim_buf_get_name(0) == "" then
    vim.ui.input(
      { prompt = "Save as: ", completion = "file", default = vim.fn.getcwd() .. "/" },
      function(name)
        if name and name ~= "" then
          vim.cmd("write " .. vim.fn.fnameescape(name))
        end
      end
    )
  else
    vim.cmd("silent! write")
  end
end

--- macOS keyboard conventions on top of Neovide's forwarded keys. Cmd-Q, Cmd-W,
--- Cmd-N, Cmd-M, Cmd-H and Cmd+Shift+[/] stay with Neovide/macOS (quit, close,
--- minimized, tabs); do not steal those.
function M.setup_keys()
  if not vim.g.neovide then
    return
  end

  local map = vim.keymap.set
  local function key(modes, lhs, rhs, desc)
    map(modes, lhs, rhs, { silent = true, desc = desc })
  end

  key("v", "<D-c>", copy_selection, "Copy to system clipboard")
  key("n", "<D-c>", copy_line, "Copy line to system clipboard")
  key("v", "<D-x>", cut_selection, "Cut to system clipboard")
  key("n", "<D-x>", cut_line, "Cut line to system clipboard")
  key({ "n", "i", "v", "c", "t" }, "<D-v>", paste, "Paste from system clipboard")

  key({ "n", "i", "v", "c" }, "<D-s>", save, "Save")
  key({ "n", "i", "v", "c" }, "<D-z>", function() vim.cmd("undo") end, "Undo")
  key({ "n", "i", "v", "c" }, "<D-Z>", function() vim.cmd("redo") end, "Redo")
  key({ "n", "i", "v", "c" }, "<D-S-z>", function() vim.cmd("redo") end, "Redo")
  key({ "n", "v" }, "<D-a>", function() vim.cmd("normal! ggVG") end, "Select all")

  key("n", "<D-p>", "<cmd>Telescope find_files<CR>", "Find files")
  key("n", "<D-f>", "<cmd>Telescope current_buffer_fuzzy_find<CR>", "Find in buffer")
  key("n", "<D-S-f>", "<cmd>Telescope live_grep<CR>", "Live grep")
  key("n", "<D-o>", "<cmd>Telescope find_files<CR>", "Open file")

  local scale = tonumber(vim.g.neovide_scale_factor) or 1.0
  local function set_scale(next)
    scale = math.max(0.5, math.min(3.0, next))
    vim.g.neovide_scale_factor = scale
  end

  key({ "n", "i", "v", "c" }, "<D-=>", function() set_scale(scale + 0.1) end, "Zoom in")
  key({ "n", "i", "v", "c" }, "<D-+>", function() set_scale(scale + 0.1) end, "Zoom in")
  key({ "n", "i", "v", "c" }, "<D-S-=>", function() set_scale(scale + 0.1) end, "Zoom in")
  key({ "n", "i", "v", "c" }, "<D-->", function() set_scale(scale - 0.1) end, "Zoom out")
  key({ "n", "i", "v", "c" }, "<D-0>", function() set_scale(1.0) end, "Reset zoom")
end

return M

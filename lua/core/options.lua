local o = vim.o

for _, provider in ipairs({ "python3_provider" }) do
  vim.g["loaded_" .. provider] = nil
  vim.cmd("runtime " .. provider)
end

o.clipboard = ""
o.cursorlineopt = "both"
o.smartindent = true
o.smarttab = true
o.tabstop = 4
o.softtabstop = 4
o.shiftwidth = 4
o.ignorecase = true
o.cursorline = true
o.timeout = true
o.timeoutlen = 1000
o.ttimeoutlen = 0
o.expandtab = true
o.linebreak = true
o.autoread = true
o.autochdir = true
o.autowriteall = true
o.breakindent = true
o.wrap = true
o.textwidth = 180
o.ruler = true
o.relativenumber = true
o.number = true
o.whichwrap = ""
o.termguicolors = true
o.showtabline = 2
o.foldenable = true
o.foldmethod = "expr"
if vim.treesitter and vim.treesitter.foldexpr then
  o.foldexpr = "v:lua.vim.treesitter.foldexpr()"
else
  o.foldexpr = "nvim_treesitter#foldexpr()"
end
o.foldlevel = 99
o.foldlevelstart = 99
o.viewoptions = "folds,cursor,curdir,slash,unix"
o.conceallevel = 1

-- Keep the undo tree across sessions. The undo file is written whenever the
-- buffer is written, so reopening a file still lets you walk back through
-- edits from earlier sessions.
o.undofile = true
o.undodir = vim.fn.stdpath("state") .. "/undo"
vim.fn.mkdir(o.undodir, "p")

-- Neovide's guifont/guifontwide/linespace and other GUI globals live in
-- core.neovide (init.lua calls setup_ui right after this file).

-- Do not block on "Press ENTER" for messages longer than 'cmdheight'. Show
-- them briefly instead; the full history is still available via :messages.
if vim.fn.exists("&messagesopt") == 1 then
  o.messagesopt = "history:500,progress:c,wait:2000"
end

-- nvim-jupyter-client logs "Initializing notebook for: <path>" at DEBUG level
-- on every .ipynb open. The path wraps in a one-line cmdline and forces a
-- hit-enter prompt before the buffer is usable. Drop TRACE/DEBUG notifications
-- globally and keep INFO and above.
local notify = vim.notify
vim.notify = function(msg, level, opts)
  level = level or vim.log.levels.INFO
  if level <= vim.log.levels.DEBUG then
    return
  end
  return notify(msg, level, opts)
end

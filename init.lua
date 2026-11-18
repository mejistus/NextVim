vim.g.mapleader = " "
vim.g.maplocalleader = " "

local config_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
vim.opt.rtp:prepend(config_dir)
package.path = config_dir .. "/lua/?.lua;" .. config_dir .. "/lua/?/init.lua;" .. package.path

-- A Neovide launched from Finder gets launchd's PATH, not the shell PATH.
-- Fill in Homebrew/local/conda/Mason paths before lazy.nvim, providers and
-- plugins shell out (git, chafa, rg/fd, formatters, latexmk, :terminal).
require("core.neovide").setup_env()

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
    vim.fn.system({
        "git",
        "clone",
        "--filter=blob:none",
        "https://github.com/folke/lazy.nvim.git",
        "--branch=stable",
        lazypath,
    })
end
vim.opt.rtp:prepend(lazypath)

-- Pin a python3 that can import pynvim before the provider is loaded below.
require("core.python").setup_host()

require("core.options")
require("core.neovide").setup_ui()
require("core.runtime")
require("core.autocmds")
require("core.highlight")
require("lazy").setup("plugins", require("configs.lazy"))
require("configs.theme").setup_persist()
vim.schedule(function()
    require("configs.theme").apply_startup_theme()
end)
require("core.keymaps")
require("core.neovide").setup_keys()

#Neovim Config (Decoupled From NvChad)

This directory is a standalone Neovim configuration based on `lazy.nvim`.

## What changed

- Removed direct dependency on `NvChad/NvChad`.
- Replaced `nvchad.*` modules with native/lazy equivalents.
- Kept your key workflows: LSP, format, DAP, `oil.nvim`, VimTeX, Treesitter, Telescope.

## Structure

- `init.lua`: bootstrap + module loading
- `lua/core`: options/autocmds/keymaps/highlight/neovide/python
- `lua/plugins`: plugin spec
- `lua/configs`: per-plugin setup

## Neovide

Neovide 0.17+ is supported. A GUI launch (Finder or "Open With") inherits
launchd's minimal PATH, not the one built by `.zshrc`; `lua/core/neovide.lua`
prepends Homebrew, `~/.local/bin`, conda envs, Mason, cargo and npm-global
before providers and plugins load. Add machine-specific directories with a
colon-separated `NEXT_VIM_GUI_PATH`.

macOS shortcuts added in Neovide:

| Key | Action |
|---|---|
| <kbd>⌘C</kbd> / <kbd>⌘X</kbd> | Copy / cut selection (current line in normal mode) |
| <kbd>⌘V</kbd> | Paste from the system clipboard |
| <kbd>⌘A</kbd> | Select all (normal / visual) |
| <kbd>⌘S</kbd> | Save (prompts for a name on an unnamed buffer) |
| <kbd>⌘Z</kbd> / <kbd>⌘⇧Z</kbd> | Undo / redo |
| <kbd>⌘P</kbd> / <kbd>⌘F</kbd> / <kbd>⌘⇧F</kbd> | Find files / find in buffer / live grep |
| <kbd>⌘O</kbd> | Find files |
| <kbd>⌘=</kbd> / <kbd>⌘-</kbd> / <kbd>⌘0</kbd> | Zoom in / out / reset |

The same module sets the GUI font fallbacks, `guifontwide` for CJK,
`linespace`, scale factor, cursor/scroll animation, hide-mouse-while-typing,
window size memory and quit confirmation.

Known limits: Neovide has no Kitty graphics protocol, so `image.nvim` stays
disabled and molten uses its text output; `oil.nvim` previews images through
`chafa` (text/ANSI), which needs the bootstrapped PATH. `kitty-scrollback.nvim`
is Kitty-only and unused in Neovide. Native tabs and menu shortcuts belong to
Neovide's own `config.toml` and are not configured here. Extra Finder "Open
With" file types currently require patching Neovide's Info.plist by hand, and
that patch is lost when Neovide updates.

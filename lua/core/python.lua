--- Pin a python3 that can import pynvim, before core.options loads the
--- provider.
---
--- Neovide launched from Finder inherits launchd's minimal PATH, not the PATH
--- built by .zshrc (including conda/pyenv). Neovim would then settle on
--- /usr/bin/python3 and the molten remote-plugin host would fail. Verify the
--- import before pinning: setting g:python3_host_prog makes Neovim skip its
--- own check, so an unusable interpreter must never be forced on it.
---
--- An explicit PYTHON3_HOST_PROG is honored in every mode, which lets a
--- remote/terminal setup pin a venv without depending on the shell PATH.
local M = {}

local function probe(prog)
  if not prog or prog == "" or vim.fn.executable(prog) == 0 then
    return nil
  end
  local script = [[
import importlib.util, sys
sys.stdout.write("%d %d" % (
    importlib.util.find_spec("neovim") is not None,
    importlib.util.find_spec("jupyter_client") is not None,
))
]]
  local ok, out = pcall(function()
    return vim.system({ prog, "-W", "ignore", "-c", script }, { text = true }):wait()
  end)
  if not ok or out.code ~= 0 then
    return nil
  end
  local has_pynvim, has_jupyter = out.stdout:match("(%d) (%d)")
  return has_pynvim == "1", has_jupyter == "1"
end

local function candidates()
  local list = {
    vim.env.PYTHON3_HOST_PROG or "",
    vim.env.CONDA_PREFIX and (vim.env.CONDA_PREFIX .. "/bin/python3") or "",
    vim.env.VIRTUAL_ENV and (vim.env.VIRTUAL_ENV .. "/bin/python3") or "",
    vim.fn.exepath("python3") or "",
    vim.fn.exepath("pynvim-python") or "",
  }

  -- Conda environments are a common home for pynvim on macOS. A GUI launch
  -- cannot see `conda activate`, so probe the usual env directories too.
  for _, root in ipairs({
    "/opt/homebrew/Caskroom/miniforge/base/envs",
    vim.fn.expand("~/miniforge3/envs"),
    vim.fn.expand("~/miniconda3/envs"),
    vim.fn.expand("~/anaconda3/envs"),
    vim.fn.expand("~/.conda/envs"),
  }) do
    vim.list_extend(list, vim.fn.glob(root .. "/*/bin/python3", false, true))
  end

  return list
end

--- Remember the interpreter and, in Neovide, put its bin directory first on
--- PATH. The shell's `python` is the active conda env (debugpy, jupyter,
--- pip); a Finder launch would otherwise resolve it to conda's base env,
--- which has none of those, so DAP's `python -m debugpy.adapter` would fail.
--- Terminal Neovim already has the shell PATH; leave it alone there.
local function pin(prog)
  vim.g.python3_host_prog = prog
  if vim.g.neovide then
    local dir = vim.fn.fnamemodify(prog, ":h")
    local seen = { [dir] = true }
    local paths = { dir }
    for _, entry in ipairs(vim.split(vim.env.PATH or "", ":", { plain = true })) do
      if entry ~= "" and not seen[entry] then
        seen[entry] = true
        paths[#paths + 1] = entry
      end
    end
    vim.env.PATH = table.concat(paths, ":")
  end
  return prog
end

function M.setup_host()
  local explicit = vim.env.PYTHON3_HOST_PROG
  if explicit and explicit ~= "" and probe(explicit) then
    return pin(explicit)
  end

  -- A terminal Neovim inherits the shell PATH and can let the provider detect
  -- the active conda/pyenv interpreter itself. Only a GUI launch needs a pin.
  if not vim.g.neovide then
    return
  end

  if type(vim.g.python3_host_prog) == "string" and vim.g.python3_host_prog ~= "" then
    return pin(vim.g.python3_host_prog)
  end

  local fallback
  for _, prog in ipairs(candidates()) do
    local has_pynvim, has_jupyter = probe(prog)
    if has_pynvim then
      if has_jupyter then
        return pin(prog)
      end
      fallback = fallback or prog
    end
  end

  -- pynvim works but jupyter_client is missing: still start the provider and
  -- let core.runtime's warning tell the user which package to install.
  if fallback then
    return pin(fallback)
  end
end

return M

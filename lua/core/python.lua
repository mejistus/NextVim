--- Pin a python3 that can import pynvim, before core.options loads the
--- provider.
---
--- Neovide launched from Finder inherits launchd's minimal PATH, not the PATH
--- built by .zshrc (including conda/pyenv). Neovim would then settle on
--- /usr/bin/python3 and the molten remote-plugin host would fail. Verify the
--- import before pinning: setting g:python3_host_prog makes Neovim skip its
--- own check, so an unusable interpreter must never be forced on it.
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

function M.setup_host()
  -- A terminal Neovim inherits the shell PATH and can let the provider detect
  -- the active conda/pyenv interpreter itself. Only a GUI launch needs a pin.
  if not vim.g.neovide then
    return
  end

  if type(vim.g.python3_host_prog) == "string" and vim.g.python3_host_prog ~= "" then
    return vim.g.python3_host_prog
  end

  local fallback
  for _, prog in ipairs(candidates()) do
    local has_pynvim, has_jupyter = probe(prog)
    if has_pynvim then
      if has_jupyter then
        vim.g.python3_host_prog = prog
        return prog
      end
      fallback = fallback or prog
    end
  end

  -- pynvim works but jupyter_client is missing: still start the provider and
  -- let core.runtime's warning tell the user which package to install.
  if fallback then
    vim.g.python3_host_prog = fallback
    return fallback
  end
end

return M

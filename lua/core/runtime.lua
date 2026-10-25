vim.env.SSL_CERT_DIR = vim.env.SSL_CERT_DIR or "/etc/ssl/certs"

local original_preview = vim.lsp.util.open_floating_preview
vim.lsp.util.open_floating_preview = function(contents, syntax, opts, ...)
  opts = opts or {}
  opts.border = opts.border or "rounded"
  opts.max_width = opts.max_width or 80
  opts.max_height = opts.max_height or 20
  opts.winhighlight = opts.winhighlight or "NormalFloat:NormalFloat,FloatBorder:FloatBorder"
  return original_preview(contents, syntax, opts, ...)
end

local original_notify = vim.notify
vim.notify = function(msg, level, notify_opts)
  if type(msg) == "string" and msg:match("Codeium") then
    return
  end
  return original_notify(msg, level, notify_opts)
end

--- Warn once when no interpreter usable by the python3 provider is around.
---
--- Neovim probes for one lazily, on the first remote-plugin call, and a set
--- g:python3_host_prog skips the probe altogether -- so the failure only shows
--- up later, as molten quietly not attaching a kernel, or as the host dying
--- with "channel was closed by the peer". Molten is the only python remote
--- plugin here, and it needs jupyter_client as well as pynvim, so check both
--- on the interpreter Neovim would pick.
local function warn_python_provider()
  local candidates = {}
  local pinned = vim.g.python3_host_prog
  if type(pinned) == "string" and pinned ~= "" then
    local prog = vim.fn.exepath(vim.fn.expand(pinned, true))
    if prog == "" then
      vim.notify(
        ("python3 provider: g:python3_host_prog (%s) is not executable, so molten/Jupyter support is off."):format(pinned),
        vim.log.levels.WARN
      )
      return
    end
    candidates[1] = prog
  else
    -- Neovim's own candidate list and order (runtime/lua/vim/provider/python.lua).
    if vim.fn.executable("pynvim-python") == 1 then
      candidates[#candidates + 1] = "pynvim-python"
    end
    local names = {
      "python3",
      "python3.14",
      "python3.13",
      "python3.12",
      "python3.11",
      "python3.10",
      "python3.9",
      "python",
    }
    for _, name in ipairs(names) do
      local prog = vim.fn.exepath(name)
      if prog ~= "" then
        candidates[#candidates + 1] = prog
      end
    end
  end

  local probe = [[
import importlib.util, sys
sys.stdout.write("%d %d" % (
    importlib.util.find_spec("neovim") is not None,
    importlib.util.find_spec("jupyter_client") is not None,
))
]]
  -- First match wins, exactly like Neovim's detection.
  for _, prog in ipairs(candidates) do
    local ok, out = pcall(function()
      return vim.system({ prog, "-W", "ignore", "-c", probe }, { text = true }):wait()
    end)
    if ok and out.code == 0 then
      local has_pynvim, has_jupyter = out.stdout:match("(%d) (%d)")
      if has_pynvim == "1" then
        if has_jupyter ~= "1" then
          vim.notify(
            ("python3 provider: %s has pynvim but not jupyter_client, so molten cannot start a kernel. Install jupyter_client there."):format(prog),
            vim.log.levels.WARN
          )
        end
        return
      end
    end
  end

  if pinned and pinned ~= "" then
    vim.notify(
      ("python3 provider: %s (g:python3_host_prog) cannot import pynvim, so molten/Jupyter support is off. Install pynvim there, or unset it and let Neovim detect one."):format(
        candidates[1]
      ),
      vim.log.levels.WARN
    )
  else
    vim.notify(
      "python3 provider: no python3 on PATH can import pynvim, so molten/Jupyter support is off. Install pynvim and jupyter_client, or set g:python3_host_prog.",
      vim.log.levels.WARN
    )
  end
end

-- Off the startup path: probing spawns python, which must not delay first paint.
vim.defer_fn(warn_python_provider, 1000)
